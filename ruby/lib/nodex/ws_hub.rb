# frozen_string_literal: true

require_relative 'websocket'
require 'json'

module Nodex
  class WSHub
    HEARTBEAT_INTERVAL = 30  # seconds between pings
    PONG_TIMEOUT       = 10  # seconds to wait for pong before closing

    def initialize
      @clients = []
      @mutex = Mutex.new
    end

    def add(client)
      @mutex.synchronize { @clients << client }
    end

    def remove(client)
      @mutex.synchronize { @clients.delete(client) }
    end

    def broadcast(message)
      @mutex.synchronize do
        @clients.reject! do |c|
          begin
            WebSocket.send_text(c, message)
            false
          rescue IOError, Errno::EPIPE, Errno::ECONNRESET
            c.close rescue nil
            true
          end
        end
      end
    end

    def client_count
      @mutex.synchronize { @clients.size }
    end

    def client_loop(client)
      add(client)
      pong_ok = true

      heartbeat = Thread.new do
        loop do
          sleep HEARTBEAT_INTERVAL
          unless pong_ok
            client.close rescue nil
            break
          end
          pong_ok = false
          WebSocket.send_ping(client, '') rescue break
        end
      end

      loop do
        frame = WebSocket.read_frame(client)
        break unless frame

        opcode, payload = frame
        case opcode
        when 0x8 # close
          WebSocket.send_close(client)
          break
        when 0x9 # ping
          WebSocket.send_pong(client, payload)
        when 0xA # pong
          pong_ok = true
        when 0x1 # text
          handle_message(client, payload)
        end
      end
    rescue IOError, Errno::ECONNRESET, Errno::EPIPE
      # disconnected
    ensure
      heartbeat.kill rescue nil
      remove(client)
      client.close rescue nil
    end

    private

    def handle_message(_client, _payload)
      # Override in subclass for interactive features
    end
  end
end
