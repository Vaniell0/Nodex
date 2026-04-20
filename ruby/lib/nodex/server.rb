# frozen_string_literal: true

require 'socket'
require 'json'
require_relative 'mime'

module Nodex
  # Minimal HTTP server — stdlib Socket, zero dependencies.
  # Can be used standalone without the full Nodex framework.
  #
  # Usage:
  #   server = Nodex::Server.new(port: 8080, public_dir: 'public')
  #
  #   server.get('/') do |req|
  #     { body: '<h1>Hello</h1>' }
  #   end
  #
  #   server.post('/api/contact') do |req|
  #     data = JSON.parse(req[:body])
  #     { body: JSON.generate(ok: true), type: 'application/json; charset=utf-8' }
  #   end
  #
  #   server.run
  class Server
    attr_reader :port, :public_dir

    MAX_BODY_SIZE = 8 * 1024 * 1024  # 8 MB

    STATUS_TEXT = {
      200 => 'OK', 201 => 'Created', 204 => 'No Content',
      301 => 'Moved Permanently', 302 => 'Found', 304 => 'Not Modified',
      400 => 'Bad Request', 403 => 'Forbidden', 404 => 'Not Found',
      405 => 'Method Not Allowed', 500 => 'Internal Server Error',
    }.freeze

    def initialize(port: 10_101, public_dir: nil)
      @port = port
      @public_dir = public_dir ? (File.realpath(File.expand_path(public_dir)) rescue File.expand_path(public_dir)) : nil
      @routes = { 'GET' => {}, 'POST' => {}, 'PUT' => {}, 'DELETE' => {} }
      @pattern_routes = { 'GET' => [], 'POST' => [], 'PUT' => [], 'DELETE' => [] }
      @middleware = []
      @sse_routes = {}
    end

    # Add middleware to the request pipeline.
    #
    #   server.use(Nodex::SessionMiddleware, secret: "s3cret")
    #   server.use(MyAuthMiddleware)
    #
    # Middleware contract:
    #   initialize(app, **opts)   — app responds to .call(req)
    #   call(req) → response hash { status:, body:, type:, headers: }
    def use(middleware_class, **opts)
      @middleware << [middleware_class, opts]
    end

    # Register an SSE endpoint.
    #
    #   server.sse('/events') do |stream, req|
    #     loop do
    #       stream.send_event("tick", data: Time.now.to_s)
    #       sleep 1
    #       break unless stream.open?
    #     end
    #   end
    def sse(path, &block)
      @sse_routes[path] = block
    end

    # Register a GET route.
    def get(path, &block)
      register_route('GET', path, &block)
    end

    # Register a POST route.
    def post(path, &block)
      register_route('POST', path, &block)
    end

    # Register a PUT route.
    def put(path, &block)
      register_route('PUT', path, &block)
    end

    # Register a DELETE route.
    def delete(path, &block)
      register_route('DELETE', path, &block)
    end

    # Start listening. Blocks until interrupted.
    def run
      @app = build_app
      socket = Socket.new(:INET, :STREAM, 0)
      socket.setsockopt(:SOCKET, :REUSEADDR, 1)
      socket.bind(Socket.sockaddr_in(@port, '0.0.0.0'))
      socket.listen(128)

      $stderr.puts "Nodex server on http://localhost:#{@port}"

      @running = true
      threads = []

      trap('INT')  { @running = false }
      trap('TERM') { @running = false }

      while @running
        ready = IO.select([socket], nil, nil, 1)
        next unless ready

        client, = begin
                    socket.accept
                  rescue IOError, Errno::EBADF, Errno::EINVAL
                    break
                  end

        threads.reject!(&:stop?)

        threads << Thread.new(client) { |c| handle_client(c) }
      end

      socket.close rescue nil
      threads.each { |t| t.join(2) }
      $stderr.puts "\nShutdown."
    end

    private

    def register_route(method, path, &block)
      if path.include?(':')
        # Pattern route: /project/:slug → regex
        regex_str = path.gsub(/:(\w+)/, '(?<\1>[^/]+)')
        regex = Regexp.new("\\A#{regex_str}\\z")
        @pattern_routes[method] << { regex: regex, handler: block }
      else
        @routes[method][path] = block
      end
    end

    def handle_client(client)
      req = parse_request(client)
      return unless req

      # SSE routes bypass middleware and normal response flow
      if req[:method] == 'GET' && (sse_handler = @sse_routes[req[:path]])
        handle_sse(client, req, sse_handler)
        return
      end

      resp = @app.call(req)
      send_response(client, resp)

      $stderr.puts "#{req[:method]} #{req[:path]} -> #{resp[:status]}"
    rescue => e
      $stderr.puts "Error: #{e.message}"
      send_response(client, { status: 500, type: 'text/plain; charset=utf-8', body: 'Internal Server Error' }) rescue nil
    ensure
      client.close rescue nil
    end

    def build_app
      app = -> (req) { dispatch(req) }
      @middleware.reverse_each do |mw_class, opts|
        inner = app
        app = mw_class.new(inner, **opts)
      end
      app
    end

    def handle_sse(client, req, handler)
      client.print "HTTP/1.1 200 OK\r\n"
      client.print "Content-Type: text/event-stream\r\n"
      client.print "Cache-Control: no-cache\r\n"
      client.print "Connection: keep-alive\r\n"
      client.print "\r\n"
      client.flush

      stream = SSEStream.new(client)
      $stderr.puts "SSE #{req[:path]} connected"
      handler.call(stream, req)
    rescue IOError, Errno::EPIPE, Errno::ECONNRESET
      # client disconnected
    ensure
      $stderr.puts "SSE #{req[:path]} disconnected"
    end

    def dispatch(req)
      method = req[:method]
      path = req[:path]

      # Exact route match
      if @routes.dig(method, path)
        result = @routes[method][path].call(req)
        return build_response(result)
      end

      # Pattern route match
      @pattern_routes.fetch(method, []).each do |route|
        match = route[:regex].match(path)
        if match
          req[:params] = match.named_captures
          result = route[:handler].call(req)
          return build_response(result)
        end
      end

      # Static file serving
      if method == 'GET' && @public_dir
        static = serve_static(path)
        return static if static
      end

      # 404
      { status: 404, type: 'text/html; charset=utf-8',
        body: "<html><body style='font-family:system-ui;display:flex;align-items:center;justify-content:center;height:100vh;margin:0;color:#999'><h1>404</h1></body></html>" }
    end

    def build_response(result)
      {
        status: result[:status] || 200,
        type: result[:type] || 'text/html; charset=utf-8',
        body: result[:body] || '',
        headers: result[:headers] || {},
      }
    end

    def serve_static(path)
      relative = path.sub(%r{^/}, '')
      file_path = File.join(@public_dir, relative)

      begin
        real_path = File.realpath(file_path)
      rescue Errno::ENOENT, Errno::EACCES, Errno::ENOTDIR
        return nil
      end

      return nil unless real_path.start_with?(@public_dir + '/')

      if File.file?(real_path)
        content_type = Nodex.mime_for(real_path)
        body = File.binread(real_path)
        return { status: 200, type: content_type, body: body }
      end

      nil
    end

    def send_response(client, resp)
      status = resp[:status] || 200
      body = resp[:body] || ''
      content_type = resp[:type] || 'text/html; charset=utf-8'

      client.print "HTTP/1.1 #{status} #{STATUS_TEXT[status] || 'OK'}\r\n"
      client.print "Content-Type: #{content_type}\r\n"
      client.print "Content-Length: #{body.bytesize}\r\n"
      (resp[:headers] || {}).each { |k, v| client.print "#{k}: #{v}\r\n" }
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
        return nil if len > MAX_BODY_SIZE
        body = client.read(len)
      end

      path, query = full_path&.split('?', 2)

      { method: method, path: path, query: query, headers: headers, body: body, params: {},
        htmx: headers['hx-request'] == 'true',
        hx_target: headers['hx-target'],
        hx_trigger: headers['hx-trigger'],
        hx_current_url: headers['hx-current-url'] }
    end
  end

  # Server-Sent Events stream object.
  #
  #   stream.send_event("update", data: {count: 5}.to_json)
  #   stream.send_event(data: "plain text")  # unnamed event
  class SSEStream
    def initialize(client)
      @client = client
      @open = true
    end

    def send_event(event = nil, data:, id: nil, retry_ms: nil)
      return unless @open
      @client.print "id: #{id}\n" if id
      @client.print "event: #{event}\n" if event
      @client.print "retry: #{retry_ms}\n" if retry_ms
      data.to_s.each_line { |line| @client.print "data: #{line.chomp}\n" }
      @client.print "\n"
      @client.flush
    rescue IOError, Errno::EPIPE, Errno::ECONNRESET
      @open = false
    end

    def open? = @open

    def close
      @open = false
      @client.close rescue nil
    end
  end
end
