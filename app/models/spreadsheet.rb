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

  PREVIEW_EXTENSIONS = %w[.xlsx .xlsm .csv .ods].freeze

  # Every sheet as it is in the file, for showing a task file on screen: [[sheet_name, rows], ...].
  # Capped so a huge workbook still opens quickly.
  def self.preview(path, ext, max_rows: 500, max_cols: 40)
    ext = ext.to_s.downcase
    raise Error, "This file type cannot be shown here" unless PREVIEW_EXTENSIONS.include?(ext)

    book = Roo::Spreadsheet.open(path, extension: ext.delete(".").to_sym)
    book.sheets.map do |name|
      sheet = book.sheet(name)
      cols = [ sheet.last_column.to_i, max_cols ].min
      rows = (1..[ sheet.last_row.to_i, max_rows ].min).map { |i| sheet.row(i).first(cols).map { |v| clean(v) } }
      [ name, rows ]
    end
  rescue Roo::Error, Zip::Error, CSV::MalformedCSVError, ArgumentError, IOError => e
    raise Error, "Could not read the file (#{e.message})"
  end

  WORKBOOK_EXTENSIONS = %w[.xlsx .xlsm .csv .ods].freeze
  MAX_SHEET_ROWS = 1000
  MAX_SHEET_COLS = 52

  # The task workbook for the built-in spreadsheet: every sheet with its cells as typed —
  # formulas kept as "=..." so the candidate sees and can change them.
  # => [{ "name" => "Sales", "cells" => [["Invoice No", "Date", ...], ...] }, ...]
  def self.workbook(path, ext)
    ext = ext.to_s.downcase
    raise Error, "This file type cannot be opened as a spreadsheet" unless WORKBOOK_EXTENSIONS.include?(ext)

    book = Roo::Spreadsheet.open(path, extension: ext.delete(".").to_sym)
    book.sheets.map do |name|
      sheet = book.sheet(name)
      rows = [ sheet.last_row.to_i, MAX_SHEET_ROWS ].min
      cols = [ sheet.last_column.to_i, MAX_SHEET_COLS ].min
      styles = {}
      cells = (1..rows).map do |r|
        (1..cols).map do |c|
          if sheet.respond_to?(:font) && (font = (sheet.font(r, c) rescue nil))
            st = { "b" => (font.bold? rescue false), "i" => (font.italic? rescue false), "u" => (font.underline? rescue false) }.select { |_, v| v }
            styles["#{r - 1}:#{c - 1}"] = st if st.any?
          end
          formula = sheet.respond_to?(:formula) ? (sheet.formula(r, c) rescue nil) : nil
          formula.present? ? "=#{formula.to_s.delete_prefix("=")}" : sheet_value(sheet.cell(r, c))
        end
      end
      { "name" => name.to_s, "cells" => cells, "styles" => styles }
    end
  rescue Roo::Error, Zip::Error, CSV::MalformedCSVError, ArgumentError, IOError => e
    raise Error, "Could not read the file (#{e.message})"
  end

  STYLE_FORMATS = %w[number currency percent comma].freeze

  # Cell formats from the built-in spreadsheet: { "row:col" => { "b" => true, "bg" => "#ffff00", "fmt" => "currency", … } }
  def self.clean_styles(styles)
    return {} unless styles.is_a?(Hash)

    styles.first(20_000).each_with_object({}) do |(key, st), out|
      next unless key.to_s.match?(/\A\d{1,4}:\d{1,2}\z/) && st.is_a?(Hash)

      clean = {}
      %w[b i u w].each { |k| clean[k] = true if st[k] == true || st[k] == "true" }
      %w[fc bg].each { |k| clean[k] = st[k].to_s.downcase if st[k].to_s.match?(/\A#\h{6}\z/) }
      clean["al"] = st["al"].to_s if %w[left center right].include?(st["al"].to_s)
      clean["fmt"] = st["fmt"].to_s if STYLE_FORMATS.include?(st["fmt"].to_s)
      clean["d"] = st["d"].to_i if st["d"].to_s.match?(/\A\d\z/)
      clean["fs"] = st["fs"].to_i if st["fs"].to_i.between?(6, 48)
      out[key.to_s] = clean if clean.any?
    end
  end

  def self.clean_widths(widths)
    return {} unless widths.is_a?(Hash)

    widths.first(MAX_SHEET_COLS).each_with_object({}) do |(col, w), out|
      out[col.to_s] = w.to_i.clamp(20, 600) if col.to_s.match?(/\A\d{1,2}\z/) && w.to_i.positive?
    end
  end

  # Excel number format codes for the ribbon's formats
  def self.format_code(st)
    d = st["d"].is_a?(Integer) ? st["d"] : { "number" => 2, "currency" => 2, "percent" => 0, "comma" => 0 }[st["fmt"]]
    decimals = d.to_i.positive? ? ".#{"0" * d}" : ""
    case st["fmt"]
    when "number" then "0#{decimals}"
    when "comma" then "#,##0#{decimals}"
    when "currency" then "\"₹\"#,##0#{decimals}"
    when "percent" then "0#{decimals}%"
    end
  end

  INDIAN_GROUPS = /(\d+?)(?=(\d\d)+(\d)(?!\d))/

  # A value as the candidate saw it in a formatted cell (₹12,34,567.50, 46%…), for HR's view.
  def self.display(value, st)
    text = value.to_s
    return text unless st.is_a?(Hash) && st["fmt"].present? && text.match?(/\A-?\d+(\.\d+)?(e[-+]?\d+)?\z/i)

    d = st["d"].is_a?(Integer) ? st["d"] : { "number" => 2, "currency" => 2, "percent" => 0, "comma" => 0 }[st["fmt"]].to_i
    n = text.to_f * (st["fmt"] == "percent" ? 100 : 1)
    formatted = ActiveSupport::NumberHelper.number_to_delimited(format("%.#{d}f", n), delimiter_pattern: INDIAN_GROUPS)
    { "currency" => "₹#{formatted}", "percent" => "#{formatted}%" }.fetch(st["fmt"], formatted)
  end

  # Inline CSS for a formatted cell in HR's view
  def self.css(st)
    return "" unless st.is_a?(Hash)

    [ ("font-weight:700" if st["b"]), ("font-style:italic" if st["i"]), ("text-decoration:underline" if st["u"]),
      ("color:#{st["fc"]}" if st["fc"]), ("background:#{st["bg"]}" if st["bg"]), ("text-align:#{st["al"]}" if st["al"]),
      ("white-space:normal" if st["w"]) ].compact.join(";")
  end

  def self.column_name(index)
    name = +""
    n = index + 1
    while n.positive?
      n, rem = (n - 1).divmod(26)
      name.prepend((65 + rem).chr)
    end
    name
  end

  def self.sheet_value(value)
    case value
    when nil then ""
    when Float then value == value.to_i ? value.to_i.to_s : value.to_s
    when Date, DateTime, Time then value.strftime("%Y-%m-%d")
    else value.to_s
    end
  end

  # The candidate's workbook from the built-in spreadsheet as an .xlsx: formulas stay formulas
  # (with the value the candidate saw cached), numbers stay numbers.
  def self.answer_xlsx(sheets)
    package = Axlsx::Package.new
    used = []
    Array(sheets).each_with_index do |sheet, i|
      name = sheet["name"].to_s.gsub(%r{[\\/?*\[\]:]}, " ").squish.first(31).presence || "Sheet#{i + 1}"
      name = "#{name.first(28)} #{i + 1}" if used.include?(name.downcase)
      used << name.downcase
      cells = Array(sheet["cells"])
      values = Array(sheet["values"])
      styles = sheet["styles"].is_a?(Hash) ? sheet["styles"] : {}
      style_ids = Hash.new do |h, st|
        options = {}
        options[:b] = true if st["b"]
        options[:i] = true if st["i"]
        options[:u] = true if st["u"]
        options[:fg_color] = st["fc"].delete("#").upcase if st["fc"]
        options[:bg_color] = st["bg"].delete("#").upcase if st["bg"]
        options[:sz] = st["fs"] if st["fs"]
        options[:format_code] = format_code(st) if st["fmt"]
        alignment = {}
        alignment[:horizontal] = st["al"].to_sym if st["al"]
        alignment[:wrap_text] = true if st["w"]
        options[:alignment] = alignment if alignment.any?
        h[st] = package.workbook.styles.add_style(options)
      end
      rows_needed = [ cells.size, styles.keys.map { |k| k.split(":").first.to_i + 1 }.max.to_i ].max
      package.workbook.add_worksheet(name: name) do |ws|
        rows_needed.times do |r|
          row = Array(cells[r]).map(&:to_s)
          width = [ row.size, styles.keys.select { |k| k.start_with?("#{r}:") }.map { |k| k.split(":").last.to_i + 1 }.max.to_i ].max
          row += [ "" ] * (width - row.size)
          ids = row.each_index.map { |c| st = styles["#{r}:#{c}"]; st.present? ? style_ids[st] : nil }
          formulas = row.map { |v| v.start_with?("=") && v.length > 1 }
          number = ->(v) { v.to_s.match?(/\A-?\d+(\.\d+)?\z/) ? (v.to_s.include?(".") ? v.to_f : v.to_i) : v }
          ws.add_row row.map { |v| number.(v) },
                     formula_values: row.each_index.map { |c| formulas[c] ? number.(Array(values[r])[c].to_s) : nil },
                     escape_formulas: formulas.map { |f| !f }, # only the candidate's own "=..." cells become formulas
                     style: ids
        end
        widths = sheet["widths"].is_a?(Hash) ? sheet["widths"] : {}
        if widths.any?
          cols = ws.rows.map { |rw| rw.cells.size }.max.to_i
          ws.column_widths(*Array.new(cols) { |c| widths[c.to_s] ? (widths[c.to_s].to_f / 7).round(1) : nil })
        end
      end
    end
    package.workbook.add_worksheet(name: "Sheet1") if package.workbook.worksheets.empty?
    package.to_stream.read
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
