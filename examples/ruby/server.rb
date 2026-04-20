#!/usr/bin/env ruby
# frozen_string_literal: true

# Nodex Ruby web server — stdlib Socket, zero dependencies.
#
# Usage:
#   ruby examples/ruby/server.rb            # production
#   ruby examples/ruby/server.rb --dev      # hot-reload + WebSocket
#   Nodex_DEV=1 ruby examples/ruby/server.rb # same

require 'socket'
require 'uri'
require 'json'
require_relative '../../ruby/lib/nodex'

include Nodex

PORT = (ENV['Nodex_PORT'] || 10_101).to_i
PROJECT_ROOT = Platform.gem_root
PAGES_DIR = File.join(PROJECT_ROOT, 'ruby', 'pages')
STATIC_DIR = File.join(PROJECT_ROOT, 'static')

DEV_MODE = ENV['Nodex_DEV'] == '1' || ARGV.include?('--dev')

if DEV_MODE
  require_relative '../lib/nodex/websocket'
  require_relative '../lib/nodex/interactive_hub'
  require_relative '../lib/nodex/file_watcher'
  require_relative '../lib/nodex/hot_reload_js'
end

MIME_TYPES = Nodex::MIME

# ── Bootstrap ─────────────────────────────────────────────────────

registry = Nodex::Registry.new
loaded = Nodex::PageLoader.load_pages(registry, PAGES_DIR)
puts "Pages: #{loaded.join(', ')}"
puts "Routes: #{registry.page_routes.join(', ')}"
puts "Components: #{registry.component_names.join(', ')}"

# ── Request handler ───────────────────────────────────────────────

def serve_static(path)
  return { status: 404, type: 'text/plain', body: "404 Not Found\n" } if path.include?('..')

  relative = path.sub('/static/', '')
  file_path = File.join(STATIC_DIR, relative)

  expanded = File.expand_path(file_path)
  static_expanded = File.expand_path(STATIC_DIR)
  if expanded.start_with?(static_expanded) && File.file?(expanded)
    body = File.binread(expanded)
    return { status: 200, type: Nodex.mime_for(expanded), body: body }
  end
  { status: 404, type: 'text/plain', body: "404 Not Found\n" }
end

def handle_request(method, path, query, body, registry)
  # POST /api/contact
  if method == 'POST' && path == '/api/contact'
    params = begin JSON.parse(body || '{}') rescue {} end
    name = params['name']
    name = 'друг' if name.nil? || name.to_s.strip.empty?
    result = { success: true, message: "Спасибо, #{name}! Ваше сообщение получено." }
    return { status: 200, type: 'application/json; charset=utf-8', body: JSON.generate(result) }
  end

  # GET /static/*
  if method == 'GET' && path.start_with?('/static/')
    return serve_static(path)
  end

  # GET /project/:id
  if method == 'GET' && path.start_with?('/project/')
    id = path.sub('/project/', '')
    if registry.has_page?('/project')
      page = registry.create_page('/project', { id: id, title: id })
      html = page.to_html
      return { status: 200, type: 'text/html; charset=utf-8', body: html }
    end
  end

  # GET — registry pages
  if method == 'GET' && registry.has_page?(path)
    page = registry.create_page(path)
    html = page.to_html
    return { status: 200, type: 'text/html; charset=utf-8', body: html }
  end

  { status: 404, type: 'text/plain', body: "404 Not Found\n" }
end

# ── WS message handler ───────────────────────────────────────────

def handle_ws_message(msg_str)
  msg = begin JSON.parse(msg_str) rescue nil end
  return nil unless msg

  case msg['type']
  when 'contact_submit'
    name = msg['name']
    name = 'друг' if name.nil? || name.to_s.strip.empty?
    { type: 'contact_response', success: true,
      message: "Спасибо, #{name}! Ваше сообщение получено." }
  end
end

# ── Hot-reload setup ──────────────────────────────────────────────

def setup_hot_reload(registry, broadcaster)
  watcher = Nodex::FileWatcher.new(
    [PAGES_DIR, STATIC_DIR],
    extensions: ['.rb', '.css', '.js', '.html'],
    interval: 0.5
  )

  watcher.on_change do |changed_files|
    ruby_files = changed_files.select { |f| f.end_with?('.rb') }
    css_files  = changed_files.select { |f| f.end_with?('.css') }

    ruby_files.each do |file|
      load file
      mod_name = File.basename(file, '.rb').split('_').map(&:capitalize).join
      if defined?(Pages) && Pages.const_defined?(mod_name)
        Pages.const_get(mod_name).register(registry)
        registry.invalidate_cache
        $stderr.puts "[hot-reload] Reloaded: #{File.basename(file)} (cache cleared)"
      end
    rescue => e
      $stderr.puts "[hot-reload] Error in #{File.basename(file)}: #{e.message}"
    end

    if css_files.any? && ruby_files.empty?
      broadcaster.call(JSON.generate({ type: 'css_reload' }))
    elsif changed_files.any?
      names = changed_files.map { |f| File.basename(f) }.join(', ')
      broadcaster.call(JSON.generate({ type: 'reload', file: names }))
    end
  end

  watcher.start
  puts "[dev] Hot-reload watching: #{PAGES_DIR}, #{STATIC_DIR}"
  watcher
end

# ── Server ────────────────────────────────────────────────────────

ws_hub = nil
file_watcher = nil

if DEV_MODE
  ws_hub = Nodex::InteractiveHub.new

  ws_hub.on('contact_submit') do |msg, _client|
    name = msg['name']
    name = 'друг' if name.nil? || name.to_s.strip.empty?
    { type: 'contact_response', success: true,
      message: "Спасибо, #{name}! Ваше сообщение получено." }
  end

  file_watcher = setup_hot_reload(registry, ->(msg) { ws_hub.broadcast(msg) })
  puts "[dev] WebSocket endpoint: ws://localhost:#{PORT}/__nodex_ws"
end

# ── HTTP helpers ──────────────────────────────────────────────────

def send_response(client, status, content_type, body)
  status_text = { 200 => 'OK', 400 => 'Bad Request', 404 => 'Not Found',
                  500 => 'Internal Server Error', 503 => 'Service Unavailable' }
  client.print "HTTP/1.1 #{status} #{status_text[status] || 'OK'}\r\n"
  client.print "Content-Type: #{content_type}\r\n"
  client.print "Content-Length: #{body.bytesize}\r\n"
  client.print "Connection: close\r\n"
  client.print "\r\n"
  client.write body
end

def parse_request(client)
  request_line = client.gets
  return nil unless request_line

  method, full_path, = request_line.split(' ')
  headers = {}
  while (line = client.gets) && line != "\r\n"
    key, value = line.split(': ', 2)
    headers[key.downcase] = value&.strip
  end

  body = nil
  if (len = headers['content-length']&.to_i) && len > 0
    body = client.read(len)
  end

  path, query = full_path&.split('?', 2)

  { method: method, path: path, query: query, headers: headers, body: body }
end

# ── Listen ────────────────────────────────────────────────────────

server = Socket.new(:INET, :STREAM, 0)
server.setsockopt(:SOCKET, :REUSEADDR, 1)
server.bind(Socket.sockaddr_in(PORT, '0.0.0.0'))
server.listen(128)

puts "Nodex server v#{Nodex.version} on http://localhost:#{PORT}"
puts "[dev] mode ON" if DEV_MODE

$running = true
threads = []

trap('INT')  { $running = false }
trap('TERM') { $running = false }

while $running
  ready = IO.select([server], nil, nil, 1)
  next unless ready

  client, _addr = begin
                    server.accept
                  rescue IOError, Errno::EBADF, Errno::EINVAL
                    break
                  end

  threads.reject!(&:stop?)

  threads << Thread.new(client) do |c|
    req = parse_request(c)
    next unless req

    # WebSocket upgrade for dev mode
    if DEV_MODE && req[:path] == '/__nodex_ws' &&
       req[:headers]['upgrade']&.downcase == 'websocket'
      if Nodex::WebSocket.handshake(c, req[:headers])
        $stderr.puts "[ws] Client connected (#{ws_hub.client_count + 1} total)"
        ws_hub.client_loop(c)
        $stderr.puts "[ws] Client disconnected (#{ws_hub.client_count} total)"
      end
      next
    end

    resp = handle_request(req[:method], req[:path], req[:query], req[:body], registry)

    # Inject hot-reload script in dev mode
    if DEV_MODE && resp[:type]&.include?('text/html')
      resp[:body] = resp[:body].sub('</body>',
        "<script>#{Nodex::HOT_RELOAD_JS}</script></body>")
    end

    send_response(c, resp[:status], resp[:type], resp[:body])
    $stderr.puts "#{req[:method]} #{req[:path]} -> #{resp[:status]}"
  rescue => e
    $stderr.puts "Error: #{e.message}"
  ensure
    unless DEV_MODE && req && req[:path] == '/__nodex_ws'
      c.close rescue nil
    end
  end
end

file_watcher&.stop
server.close rescue nil
threads.each { |t| t.join(2) }
puts "\nShutdown."
