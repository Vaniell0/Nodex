# frozen_string_literal: true

# DOCX/ODT export for FWUI nodes — native C++ rendering.
# Zero dependencies: ZIP + XML generated in C++.
module FWUI
  class Node
    # Render this node tree as a DOCX binary string.
    #   File.binwrite("out.docx", node.to_docx)
    #   File.binwrite("out.docx", node.to_docx("page_size" => "A4"))
    def to_docx(opts = nil)
      NativeDocx.render_docx(self, opts)
    end

    # Render this node tree as an ODT binary string.
    #   File.binwrite("out.odt", node.to_odt)
    #   File.binwrite("out.odt", node.to_odt("page_size" => "A4"))
    def to_odt(opts = nil)
      NativeDocx.render_odt(self, opts)
    end
  end

  module Native
    # Render a node tree to DOCX format (binary string).
    #   docx = FWUI::Native.to_docx(node)
    #   docx = FWUI::Native.to_docx(node, "page_size" => "A4")
    def self.to_docx(node, opts = nil)
      NativeDocx.render_docx(node, opts)
    end

    # Render a node tree to ODT format (binary string).
    #   odt = FWUI::Native.to_odt(node)
    #   odt = FWUI::Native.to_odt(node, "page_size" => "A4")
    def self.to_odt(node, opts = nil)
      NativeDocx.render_odt(node, opts)
    end
  end
end
