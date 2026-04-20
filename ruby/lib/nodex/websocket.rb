# frozen_string_literal: true

require 'digest'
require 'base64'

module Nodex
  module WebSocket
    GUID = "258EAFA5-E914-47DA-95CA-5AB5DC799C07"
    MAX_FRAME_SIZE = 16 * 1024 * 1024  # 16 MB

    module_function

    def handshake(client, headers)
      key = headers['sec-websocket-key']
      return false unless key

      accept = Base64.strict_encode64(
        Digest::SHA1.digest(key.strip + GUID)
      )

      client.print "HTTP/1.1 101 Switching Protocols\r\n" \
                   "Upgrade: websocket\r\n" \
                   "Connection: Upgrade\r\n" \
                   "Sec-WebSocket-Accept: #{accept}\r\n" \
                   "\r\n"
      true
    end

    def read_frame(client)
      first_byte = client.getbyte
      return nil unless first_byte

      opcode = first_byte & 0x0F

      second_byte = client.getbyte
      return nil unless second_byte

      masked = (second_byte & 0x80) != 0
      length = second_byte & 0x7F

      if length == 126
        raw = client.read(2)
        return nil unless raw && raw.bytesize == 2
        length = raw.unpack1('n')
      elsif length == 127
        raw = client.read(8)
        return nil unless raw && raw.bytesize == 8
        length = raw.unpack1('Q>')
      end

      raise "WebSocket frame too large (#{length} bytes)" if length > MAX_FRAME_SIZE
      raise "unmasked frame from client (RFC 6455 violation)" unless masked

      mask_key = nil
      if masked
        raw = client.read(4)
        return nil unless raw && raw.bytesize == 4
        mask_key = raw.bytes
      end

      payload = length > 0 ? (client.read(length) || '') : ''

      if masked && mask_key
        payload = payload.bytes.each_with_index.map { |b, i|
          b ^ mask_key[i % 4]
        }.pack('C*')
      end

      [opcode, payload]
    end

    def send_text(client, message)
      send_frame(client, 0x81, message.encode('UTF-8'))
    end

    def send_close(client, code = 1000)
      frame = [0x88, 2, code].pack('CCn')
      client.write(frame) rescue nil
    end

    def send_ping(client, data = '')
      send_frame(client, 0x89, data)
    end

    def send_pong(client, data = '')
      send_frame(client, 0x8A, data)
    end

    def send_frame(client, opcode_byte, payload)
      frame = [opcode_byte].pack('C')
      size = payload.bytesize

      if size < 126
        frame << [size].pack('C')
      elsif size < 65_536
        frame << [126, size].pack('Cn')
      else
        frame << [127, size].pack('CQ>')
      end

      frame << payload
      client.write(frame)
    end
    private_class_method :send_frame
  end
end
