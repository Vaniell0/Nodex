# frozen_string_literal: true

module Nodex
  # Common MIME types for static file serving.
  # Usage: Nodex::MIME['.css'] → "text/css; charset=utf-8"
  MIME = {
    '.css'  => 'text/css; charset=utf-8',
    '.js'   => 'application/javascript; charset=utf-8',
    '.mjs'  => 'application/javascript; charset=utf-8',
    '.html' => 'text/html; charset=utf-8',
    '.htm'  => 'text/html; charset=utf-8',
    '.json' => 'application/json; charset=utf-8',
    '.xml'  => 'application/xml; charset=utf-8',
    '.txt'  => 'text/plain; charset=utf-8',
    '.csv'  => 'text/csv; charset=utf-8',
    '.png'  => 'image/png',
    '.jpg'  => 'image/jpeg',
    '.jpeg' => 'image/jpeg',
    '.gif'  => 'image/gif',
    '.webp' => 'image/webp',
    '.svg'  => 'image/svg+xml',
    '.ico'  => 'image/x-icon',
    '.avif' => 'image/avif',
    '.woff' => 'font/woff',
    '.woff2' => 'font/woff2',
    '.ttf'  => 'font/ttf',
    '.otf'  => 'font/otf',
    '.pdf'  => 'application/pdf',
    '.zip'  => 'application/zip',
    '.wasm' => 'application/wasm',
    '.map'  => 'application/json',
  }.freeze

  # Lookup with fallback.
  def self.mime_for(path)
    MIME[File.extname(path).downcase] || 'application/octet-stream'
  end
end
