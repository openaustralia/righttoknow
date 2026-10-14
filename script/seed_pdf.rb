# frozen_string_literal: true

# A minimal PDF writer for script/seed_test_data.rb: single page, Helvetica,
# plain ASCII text, no dependencies. The host app has no PDF-generating gem
# and its spec fixtures are UK letters, which read wrongly on an Australian
# demo site, so seeded authority responses get letters composed for the
# request they answer instead.
#
# Deliberately not a general PDF library: it does what a fake decision letter
# needs (word-wrapped paragraphs on one A4 page) and nothing else.
module SeedPdf
  PAGE_WIDTH = 595
  PAGE_HEIGHT = 842
  MARGIN = 56
  FONT_SIZE = 11
  LEADING = 14
  WRAP_AT = 88
  MAX_LINES = ((PAGE_HEIGHT - (2 * MARGIN)) / LEADING).floor

  module_function

  # Returns the binary PDF for +text+, a string of paragraphs separated by
  # blank lines. Anything past one page is dropped with a marker line, since
  # a seed letter never needs to be that long.
  def render(text)
    lines = wrap(text)
    lines = lines.first(MAX_LINES - 1) << '[letter truncated]' if lines.size > MAX_LINES

    content = content_stream(lines)
    objects = [
      '<< /Type /Catalog /Pages 2 0 R >>',
      '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
      "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 #{PAGE_WIDTH} #{PAGE_HEIGHT}] " \
      '/Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>',
      "<< /Length #{content.bytesize} >>\nstream\n#{content}\nendstream",
      '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>'
    ]

    assemble(objects)
  end

  def wrap(text)
    text.to_s.each_line(chomp: true).flat_map do |paragraph|
      next [''] if paragraph.strip.empty?

      paragraph.strip.scan(/\S.{0,#{WRAP_AT - 1}}(?=\s|\z)/).map(&:strip)
    end
  end

  def content_stream(lines)
    body = lines.map { |line| "(#{escape(line)}) Tj T*" }.join("\n")
    "BT\n/F1 #{FONT_SIZE} Tf\n#{LEADING} TL\n" \
      "#{MARGIN} #{PAGE_HEIGHT - MARGIN} Td\n#{body}\nET"
  end

  # PDF string literals need backslash, parentheses escaped; everything else is
  # forced to ASCII so the built-in Helvetica encoding can show it.
  def escape(line)
    line.encode('ASCII', invalid: :replace, undef: :replace, replace: '?')
        .gsub(/[\\()]/) { |char| "\\#{char}" }
  end

  def assemble(objects)
    pdf = +"%PDF-1.4\n"
    offsets = []

    objects.each_with_index do |object, index|
      offsets << pdf.bytesize
      pdf << "#{index + 1} 0 obj\n#{object}\nendobj\n"
    end

    xref_offset = pdf.bytesize
    pdf << "xref\n0 #{objects.size + 1}\n0000000000 65535 f \n"
    offsets.each { |offset| pdf << format("%010d 00000 n \n", offset) }
    pdf << "trailer\n<< /Size #{objects.size + 1} /Root 1 0 R >>\n" \
           "startxref\n#{xref_offset}\n%%EOF\n"
    pdf.b
  end
end
