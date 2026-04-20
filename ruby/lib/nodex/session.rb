# frozen_string_literal: true

require 'openssl'

module Nodex
  # Thread-safe in-memory session store with HMAC-signed cookie IDs.
  #
  #   store = Nodex::SessionStore.new("my-secret-key")
  #   sid   = store.create                    # => "a1b2c3..."
  #   store.save(sid, { user_id: 42 })
  #   store.load(sid)                         # => { user_id: 42 }
  #   signed = store.sign(sid)                # => "a1b2c3....<hmac>"
  #   store.verify(signed)                    # => "a1b2c3..." or nil
  class SessionStore
    def initialize(secret)
      @secret = secret
      @store = {}
      @mutex = Mutex.new
    end

    def load(sid)
      @mutex.synchronize { @store[sid]&.dup || {} }
    end

    def save(sid, data)
      @mutex.synchronize { @store[sid] = data.dup }
    end

    def create
      sid = OpenSSL::Random.random_bytes(16).unpack1('H*')
      @mutex.synchronize { @store[sid] = {} }
      sid
    end

    def destroy(sid)
      @mutex.synchronize { @store.delete(sid) }
    end

    def sign(sid)
      hmac = OpenSSL::HMAC.hexdigest('SHA256', @secret, sid)
      "#{sid}.#{hmac}"
    end

    def verify(signed)
      return nil unless signed.is_a?(String)
      sid, hmac = signed.split('.', 2)
      return nil unless sid && hmac
      expected = OpenSSL::HMAC.hexdigest('SHA256', @secret, sid)
      return nil unless secure_compare(expected, hmac)
      sid
    end

    private

    def secure_compare(a, b)
      return false unless a.bytesize == b.bytesize
      result = 0
      a.bytes.zip(b.bytes) { |x, y| result |= x ^ y }
      result == 0
    end
  end

  # Middleware that loads/saves sessions via signed cookies.
  #
  #   server.use(Nodex::SessionMiddleware, secret: "s3cret")
  #
  #   server.get('/') do |req|
  #     visits = (req[:session][:visits] || 0) + 1
  #     req[:session][:visits] = visits
  #     { body: "Visit ##{visits}" }
  #   end
  class SessionMiddleware
    COOKIE_NAME = 'nodex_sid'

    def initialize(app, secret:)
      @app = app
      @store = SessionStore.new(secret)
    end

    def call(req)
      cookie = req[:headers]&.[]('cookie') || ''
      signed_sid = extract_cookie(cookie, COOKIE_NAME)
      sid = @store.verify(signed_sid)

      if sid
        req[:session] = @store.load(sid)
      else
        sid = @store.create
        req[:session] = {}
      end
      req[:session_id] = sid

      resp = @app.call(req)

      @store.save(sid, req[:session])
      signed = @store.sign(sid)
      set_cookie = "#{COOKIE_NAME}=#{signed}; Path=/; HttpOnly; SameSite=Lax"
      resp[:headers] = (resp[:headers] || {}).merge('Set-Cookie' => set_cookie)

      resp
    end

    private

    def extract_cookie(header, name)
      header.split(';').each do |pair|
        k, v = pair.strip.split('=', 2)
        return v if k == name
      end
      nil
    end
  end
end
