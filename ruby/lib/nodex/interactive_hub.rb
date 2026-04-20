# frozen_string_literal: true

require_relative 'ws_hub'

module Nodex
  class InteractiveHub < WSHub
    def initialize
      super
      @handlers = {}
      @handlers_mutex = Mutex.new
    end

    def on(event_type, &handler)
      @handlers_mutex.synchronize { @handlers[event_type.to_s] = handler }
    end

    def add(client)
      super
      broadcast(JSON.generate({ type: 'visitor_count', count: client_count }))
    end

    def remove(client)
      super
      broadcast(JSON.generate({ type: 'visitor_count', count: client_count }))
    end

    private

    def handle_message(client, payload)
      msg = JSON.parse(payload) rescue return
      event_type = msg['type']
      return unless event_type

      handler = @handlers_mutex.synchronize { @handlers[event_type] }
      return unless handler

      response = handler.call(msg, client)
      WebSocket.send_text(client, JSON.generate(response)) if response
    rescue JSON::ParserError
      # ignore malformed messages
    end
  end
end
