# frozen_string_literal: true

# nodex-office — DOCX/ODT/OMML writers for Nodex.
#
# Loads:
#   require 'nodex'
#   require 'nodex/office'
#
# After load:
#   node.to_docx(path, preset: :gost)
#   node.to_odt(path)
#   node.to_pdf(path)   # via soffice
#
# Pure Ruby, zero gem dependencies (only stdlib + Zlib).

require 'nodex'

require_relative 'office/docx'
require_relative 'office/omml'
require_relative 'office/odt'

module Nodex
  class Node
    # Render to DOCX (pure Ruby, zero deps).
    def to_docx(output_path = nil, preset: nil, **opts)
      data = Nodex::DocxWriter.render(self, preset: preset, **opts)
      output_path ? File.binwrite(output_path, data) : data
    end

    # Render to ODT (pure Ruby, zero deps).
    def to_odt(output_path = nil, preset: nil, **opts)
      data = Nodex::OdtWriter.render(self, preset: preset, **opts)
      output_path ? File.binwrite(output_path, data) : data
    end

    # Render to PDF via DOCX → LibreOffice conversion. Requires `soffice` in PATH.
    def to_pdf(output_path = nil, preset: nil, **opts)
      require 'tempfile'
      require 'fileutils'

      docx_data = to_docx(preset: preset, **opts)
      tmp = Tempfile.new(['nodex', '.docx'])
      tmp.binmode
      tmp.write(docx_data)
      tmp.close

      tmp_dir = Dir.mktmpdir('nodex-pdf')
      result = system('soffice', '--headless', '--convert-to', 'pdf',
                      '--outdir', tmp_dir, tmp.path,
                      out: File::NULL, err: File::NULL)
      raise 'soffice not found or conversion failed (is LibreOffice installed?)' unless result

      pdf_path = File.join(tmp_dir, File.basename(tmp.path, '.docx') + '.pdf')
      pdf_data = File.binread(pdf_path)

      FileUtils.rm_rf(tmp_dir)
      tmp.unlink

      output_path ? File.binwrite(output_path, pdf_data) : pdf_data
    end
  end
end
