# frozen_string_literal: true

# Nodex::Doc — document-oriented API with presets for academic documents.
#
#   docx = Nodex::Doc.to_docx(tree, preset: :gost)
#   odt  = Nodex::Doc.to_odt(tree, preset: :gost, header: "My Report")
module Nodex
  module Doc
    # Russian academic standard (ГОСТ 7.32-2017)
    GOST = {
      "page_size" => "A4",
      "margin_top" => "20mm", "margin_bottom" => "20mm",
      "margin_left" => "30mm", "margin_right" => "15mm",
      "default_font" => "Times New Roman",
      "default_font_size" => "14pt",
      "line_spacing" => "1.5",
      "first_line_indent" => "1.25cm",
    }.freeze

    # Generic academic paper (APA/IEEE style)
    ACADEMIC = {
      "page_size" => "A4",
      "margin_top" => "25mm", "margin_bottom" => "25mm",
      "margin_left" => "25mm", "margin_right" => "25mm",
      "default_font" => "Times New Roman",
      "default_font_size" => "12pt",
      "line_spacing" => "2.0",
      "first_line_indent" => "1.27cm",
    }.freeze

    # Technical / business report
    REPORT = {
      "page_size" => "A4",
      "margin_top" => "25mm", "margin_bottom" => "25mm",
      "margin_left" => "20mm", "margin_right" => "20mm",
      "default_font" => "Calibri",
      "default_font_size" => "11pt",
      "line_spacing" => "1.15",
    }.freeze

    # Formal letter
    LETTER = {
      "page_size" => "A4",
      "margin_top" => "20mm", "margin_bottom" => "20mm",
      "margin_left" => "25mm", "margin_right" => "25mm",
      "default_font" => "Calibri",
      "default_font_size" => "11pt",
      "line_spacing" => "1.0",
    }.freeze

    def self.page_break = Nodex.node("__page_break__")

    def self.to_docx(node, preset: nil, **opts)
      config = (preset ? const_get(preset.to_s.upcase) : {}).merge(string_keys(opts))
      NativeDocx.render_docx(node, config)
    end

    def self.to_odt(node, preset: nil, **opts)
      config = (preset ? const_get(preset.to_s.upcase) : {}).merge(string_keys(opts))
      NativeDocx.render_odt(node, config)
    end

    private_class_method def self.string_keys(h)
      h.transform_keys(&:to_s)
    end
  end
end
