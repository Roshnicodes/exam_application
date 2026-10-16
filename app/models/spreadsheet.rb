require "csv"

# Reads uploaded CSV / Excel files and builds .xlsx downloads.
module Spreadsheet
  class Error < StandardError; end

  EXTENSIONS = %w[.csv .xlsx .xls].freeze

  # Returns [[row_number, { "normalized header" => value }], ...] for the first sheet.
  def self.rows(file)
    sheets(file).first&.last || raise(Error, "The file is empty")
  end

  # Returns [[sheet_name, rows], ...] for every sheet that has a header row and data.
  def self.sheets(file)
    raise Error, "Please choose a file to upload" if file.blank?

    ext = File.extname(file.original_filename.to_s).downcase
    raise Error, "Unsupported file type. Upload a .xlsx or .csv file" unless EXTENSIONS.include?(ext)

    book = Roo::Spreadsheet.open(file.path, extension: ext.delete(".").to_sym)
    result = book.sheets.filter_map do |name|
      sheet = book.sheet(name)
      next if sheet.last_row.to_i < 2

      # "Correct Answer (A/B/C/D)" -> "correct answer": hints in brackets don't matter
      headers = sheet.row(1).map { |h| h.to_s.gsub(/\(.*?\)/, "").squish.downcase }
      rows = (2..sheet.last_row).map do |i|
        values = sheet.row(i).map { |v| clean(v) }
        [ i, headers.zip(values).to_h ]
      end
      [ name, rows ]
    end
    raise Error, "The file is empty" if result.empty?

    result
  rescue Roo::Error, Zip::Error, CSV::MalformedCSVError, ArgumentError => e
    raise Error, "Could not read the file (#{e.message})"
  end

  EXCEL_ERRORS = /\A#(N\/A|REF!|VALUE!|DIV\/0!|NAME\?|NULL!|NUM!)\z/

  # Whole numbers come back from Excel as floats (5.0); Excel error cells become blank.
  def self.clean(value)
    value = value.to_i if value.is_a?(Float) && value == value.to_i
    value.to_s.squish.sub(EXCEL_ERRORS, "")
  end

  # Builds an .xlsx with a styled header row. `notes` adds an Instructions sheet.
  # `highlight` lists column indexes drawn in green (e.g. the answer column).
  def self.build(sheet_name, headers, rows = [], widths: nil, notes: nil, highlight: [])
    package = Axlsx::Package.new
    book = package.workbook
    header_style = book.styles.add_style(b: true, fg_color: "FFFFFF", bg_color: "6D4AFF", alignment: { horizontal: :center, vertical: :center, wrap_text: true })
    key_header = book.styles.add_style(b: true, fg_color: "FFFFFF", bg_color: "059669", alignment: { horizontal: :center, vertical: :center, wrap_text: true })
    key_cell = book.styles.add_style(b: true, fg_color: "065F46", bg_color: "D1FAE5", alignment: { horizontal: :center })
    book.add_worksheet(name: sheet_name) do |ws|
      ws.add_row headers, style: headers.each_index.map { |i| highlight.include?(i) ? key_header : header_style }, height: 30
      rows.each do |r|
        ws.add_row r, types: Array.new(r.size, :string), style: r.each_index.map { |i| key_cell if highlight.include?(i) }
      end
      ws.column_widths(*widths) if widths
      ws.sheet_view.pane { |p| p.top_left_cell = "A2"; p.state = :frozen; p.y_split = 1 }
    end
    if notes
      book.add_worksheet(name: "Instructions") do |ws|
        notes.each { |line| ws.add_row [ line ] }
        ws.column_widths 110
      end
    end
    package.to_stream.read
  end
end
