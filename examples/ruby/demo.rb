#!/usr/bin/env ruby
# frozen_string_literal: true

# Nodex Ruby DSL demo — minimal example.
#
# Usage:
#   ruby examples/ruby/demo.rb

require_relative '../../ruby/lib/nodex'

puts "Nodex version: #{Nodex.version}"
puts

# ── Basic elements with pipe operator ──────────────────────

extend Nodex::DSL

title = h1("Hello from Nodex") | Bold() | Color("#1a1a2e") | Center()
puts "=== Single element ==="
puts title.to_html
puts

# ── Full page ──────────────────────────────────────────────

page = document("Nodex Example",
  head: [
    style_elem("body { font-family: system-ui, sans-serif; margin: 0; color: #333; }
    .navbar { display: flex; gap: 16px; padding: 12px 24px; background: #fff; border-bottom: 1px solid #eee; }
    .nav-link { color: inherit; text-decoration: none; }
    .container { max-width: 800px; margin: 0 auto; padding: 40px 24px; }
    .footer { text-align: center; padding: 24px; border-top: 1px solid #eee; color: #999; }"),
  ],
  body: [
    nav([
      a("Home",    href: "/")       | AddClass("nav-link"),
      a("About",   href: "#about")  | AddClass("nav-link"),
      a("Contact", href: "#contact")| AddClass("nav-link"),
    ]) | Class("navbar"),

    div([
      title,
      p("Declarative HTML generation — zero dependencies, pure Ruby.") | Center() | Color("#666"),
      separator,
      section([
        h2("Features"),
        ul([
          li("50+ element factories"),
          li("Pipe operator: h1(\"...\") | Bold() | Color(\"red\")"),
          li("Component registry with auto-loading"),
          li("Built-in HTTP server with hot-reload"),
        ]),
      ]) | Id("about") | Padding("20px"),
    ]) | Class("container"),

    footer([
      p("Built with Nodex") | Center(),
    ]) | Class("footer"),
  ]
)

puts "=== Full page ==="
puts page.to_html
