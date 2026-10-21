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
    sheets = [ { name: sheet_name, headers: headers, rows: rows, widths: widths, highlight: highlight } ]
    sheets << { name: "Instructions", headers: nil, rows: notes.map { |line| [ line ] }, widths: [ 110 ] } if notes
    build_book(sheets)
  end

  # Several sheets in one workbook: [{ name:, headers:, rows:, widths:, highlight: }, ...]
  def self.build_book(sheets)
    package = Axlsx::Package.new
    book = package.workbook
    header_style = book.styles.add_style(b: true, fg_color: "FFFFFF", bg_color: "047857", alignment: { horizontal: :center, vertical: :center, wrap_text: true })
    key_header = book.styles.add_style(b: true, fg_color: "FFFFFF", bg_color: "0E7490", alignment: { horizontal: :center, vertical: :center, wrap_text: true })
    key_cell = book.styles.add_style(b: true, fg_color: "065F46", bg_color: "D1FAE5", alignment: { horizontal: :center })
    sheets.each do |sheet|
      highlight = sheet[:highlight] || []
      book.add_worksheet(name: sheet[:name].to_s.first(31)) do |ws|
        if sheet[:headers]
          ws.add_row sheet[:headers], style: sheet[:headers].each_index.map { |i| highlight.include?(i) ? key_header : header_style }, height: 30
        end
        sheet[:rows].each do |r|
          r = r.map { |v| v.nil? ? "" : v.to_s }
          ws.add_row r, types: Array.new(r.size, :string), style: r.each_index.map { |i| key_cell if highlight.include?(i) }
        end
        ws.column_widths(*sheet[:widths]) if sheet[:widths]
        if sheet[:headers]
          ws.sheet_view.pane { |p| p.top_left_cell = "A2"; p.state = :frozen; p.y_split = 1 }
          ws.auto_filter = "A1:#{Axlsx.col_ref(sheet[:headers].size - 1)}#{[ sheet[:rows].size + 1, 2 ].max}" if sheet[:rows].any?
        end
      end
    end
    package.to_stream.read
  end
end
