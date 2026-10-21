require "zip"

# Reads an MCQ question paper in any common format — Word (.docx), PDF, text, Excel / CSV —
# and turns it into questions. Understands:
#   1. Question text            (numbering 1. / 1) / Q1. / Question 1:, tables and bullet points kept)
#   A. option  B. option ...    (one per line or several on one line)
#   Answer: B                   (after a question, or an "Answer key" list at the end: 1-B, 2) C ...)
# A single option written in bold / highlighted / underlined (Word), or marked ✓ / *, also counts as
# the correct answer. Questions whose answer isn't found come back with correct_index nil for HR to pick.
class QuestionPaperParser
  class Error < StandardError; end

  EXTENSIONS = %w[.docx .pdf .txt .xlsx .xls .csv].freeze
  Result = Struct.new(:title, :duration, :questions, :warnings, keyword_init: true)

  MARK_ON = "\u0001".freeze  # wraps text that is visually marked in Word (bold / highlight / underline)
  MARK_OFF = "\u0002".freeze
  TICK = /\s*(?:✓|✔|☑|\(correct\)|\*)\s*/i

  QUESTION = /\A\s*(?:Q(?:ues(?:tion)?)?\s*\.?\s*(?:no\.?\s*)?)?(\d{1,3})\s*[.):\-]\s*(\S.*)\z/i
  OPTION_START = /\A\s*\(?([A-Fa-f])[.)]\s+/
  ANSWER = /\A\s*(?:correct\s+)?(?:ans(?:wer)?|key|correct\s+option)\s*[:\-.]?\s*\(?([A-Fa-f])\)?(?![A-Za-z])/i
  ANSWER_KEY_HEADING = /\A\s*(?:answer\s*key|answers?|key\s*answers?|solutions?)\s*:?\s*\z/i
  KEY_PAIR = /(\d{1,3})\s*[.):\-–]?\s*\(?([A-Fa-f])\)?(?![A-Za-z0-9])/
  SKIP_LINE = /\A\s*(?:section\b.*|part\s+[A-Z0-9]\b.*|questions?\s+\d+\s*(?:[–\-]|to)\s*\d+\s*:?)\s*\z/i
  RANGE = /questions?\s+(\d+)\s*(?:[–\-]|to|and|&)\s*(\d+)/i

  def self.parse(file)
    new(file).parse
  end

  def initialize(file)
    raise Error, "Please choose a file to upload" if file.blank?

    @file = file
    @ext = File.extname(file.original_filename.to_s).downcase
  end

  def parse
    case @ext
    when ".xlsx", ".xls", ".csv" then from_sheet
    when ".docx" then from_lines(docx_lines)
    when ".pdf" then from_lines(pdf_lines)
    when ".txt" then from_lines(File.read(@file.path, encoding: "bom|utf-8").scrub.lines.map(&:chomp))
    when ".doc" then raise Error, "Old Word (.doc) files can't be read. Open it in Word, Save As .docx (or PDF) and upload that."
    else raise Error, "Unsupported file. Upload Word (.docx), PDF, Excel (.xlsx / .csv) or text (.txt)."
    end
  end

  private
    # ---------------------------------------------------------------- readers
    def docx_lines
      xml = Zip::File.open(@file.path) { |zip| zip.find_entry("word/document.xml")&.get_input_stream&.read }
      raise Error, "This doesn't look like a Word (.docx) file" unless xml

      doc = Nokogiri::XML(xml)
      ns = { "w" => "http://schemas.openxmlformats.org/wordprocessingml/2006/main" }
      body = doc.at_xpath("//w:body", ns)
      body.element_children.flat_map do |node|
        case node.name
        when "p" then docx_paragraph(node, ns)
        when "tbl"
          node.xpath("./w:tr", ns).map do |tr|
            tr.xpath("./w:tc", ns).map { |tc| tc.xpath(".//w:t", ns).map(&:text).join.squish }.join(" | ")
          end
        else []
        end
      end
    rescue Zip::Error => e
      raise Error, "Could not read the Word file (#{e.message})"
    end

    # Paragraph text with tabs kept; list items get a bullet so they aren't read as question numbers.
    # Bold / highlighted / underlined text is wrapped in markers (an option counts as the answer only
    # when it is the one marked option of its question).
    def docx_paragraph(p, ns)
      runs = p.xpath(".//w:r", ns).map do |r|
        text = r.children.map { |c| { "t" => c.text, "tab" => "\t", "br" => "\n" }[c.name] }.join
        props = r.at_xpath("./w:rPr", ns)
        marked = props && (props.at_xpath("./w:highlight", ns) || props.at_xpath("./w:u[not(@w:val='none')]", ns) ||
                           props.at_xpath("./w:shd[@w:fill and not(@w:fill='auto') and not(@w:fill='FFFFFF')]", ns) ||
                           props.at_xpath("./w:b[not(@w:val='0') and not(@w:val='false')]", ns))
        [ text, !!marked ]
      end
      text = runs.map { |t, m| m && t.strip.present? ? "#{MARK_ON}#{t}#{MARK_OFF}" : t }.join
      text = "• #{text}" if p.at_xpath("./w:pPr/w:numPr", ns) && text.strip.present?
      text.split("\n")
    end

    def pdf_lines
      PDF::Reader.new(@file.path).pages.flat_map { |page| page.text.lines.map(&:rstrip) }
    rescue PDF::Reader::MalformedPDFError, PDF::Reader::UnsupportedFeatureError => e
      raise Error, "Could not read the PDF (#{e.message})"
    end

    # Excel / CSV with the template columns. A missing answer is left for HR to pick instead of failing.
    def from_sheet
      questions = Spreadsheet.rows(@file).filter_map do |_line, row|
        body = row["question"].to_s.strip
        options = Question::LETTERS.map { |l| row["option #{l.downcase}"].to_s.strip }.reject(&:blank?)
        next if body.blank? || options.size < 2

        answer = Quiz::ANSWER_COLUMNS.lazy.map { |k| row[k] }.find(&:present?).to_s.strip
        { body: body, options: options, correct_index: Quiz.answer_index(answer, options),
          marks: row["marks"].to_i.positive? ? row["marks"].to_i : 1 }
      end
      raise Error, "No questions found. Use the columns Question, Option A–D, Correct Answer, Marks." if questions.empty?

      Result.new(title: nil, duration: nil, questions: questions, warnings: [])
    rescue Spreadsheet::Error => e
      raise Error, e.message
    end

    # ---------------------------------------------------------------- text paper
    def from_lines(lines)
      lines = lines.map { |l| l.to_s.tr(" ", " ").rstrip }
      header = []
      questions = []
      context = [] # text between one question's options and the next question (a shared passage)
      passages = []
      key = {}
      in_key = false
      current = nil

      lines.each do |raw|
        line = raw.strip
        next if line.empty?

        plain = unmark(line)
        if in_key || plain.match?(ANSWER_KEY_HEADING)
          in_key = true
          plain.scan(KEY_PAIR) { |n, l| key[n.to_i] = l.upcase }
          next
        end

        if current && (m = plain.match(ANSWER)) && (current[:options].size >= 2)
          current[:answer] = m[1].upcase
          next
        end

        if (m = plain.match(QUESTION)) && restart?(m[1].to_i, questions, current)
          header.concat(questions.flat_map { |q| q[:body] } + Array(current&.dig(:body)))
          questions.clear
          current = nil
        end

        if (m = plain.match(QUESTION)) && next_number?(m[1].to_i, questions, current) && !option_line?(plain, current)
          finish(current, questions)
          current = { number: m[1].to_i, body: [ unmark(m[2]).sub(TICK, " ").strip ], options: [], marks: [] }
          if context.any?
            range = context.join(" ").match(RANGE)
            passages << { text: context.join("\n"), range: range ? [ range[1].to_i, range[2].to_i ] : [ current[:number], current[:number] ] }
            context = []
          end
          next
        end

        next if plain.match?(SKIP_LINE)

        if current && option_line?(plain, current)
          add_options(line, current)
        elsif current.nil?
          header << plain
        elsif current[:options].size >= 2
          context << plain.delete_prefix("• ")
        elsif current[:options].any?
          current[:options][-1] += " #{plain}" # an option that wrapped onto the next line
        else
          current[:body] << plain
        end
      end
      finish(current, questions)

      build_result(header, questions, passages, key)
    end

    def next_number?(number, questions, current)
      last = current&.dig(:number) || questions.last&.dig(:number)
      last.nil? ? number.between?(1, 5) : number == last + 1
    end

    # "1." again before any question had options: the earlier numbered lines were instructions.
    def restart?(number, questions, current)
      number == 1 && current && (questions + [ current ]).all? { |q| q[:options].empty? }
    end

    def option_line?(plain, current)
      return false unless current && (m = plain.match(OPTION_START))

      m[1].upcase == Question::LETTERS[current[:options].size]
    end

    # "A. 320\tB. 340  C. 360 D. 400" -> four options (letters must come in order A, B, C...).
    def add_options(line, current)
      rest = line.strip
      loop do
        letter = Question::LETTERS[current[:options].size]
        start = rest.match(/\A[#{MARK_ON}#{MARK_OFF}]*\(?#{letter}[.)]\s*/i) or break
        prefix = start[0]
        rest = rest[start[0].size..]
        nxt = Question::LETTERS[current[:options].size + 1]
        split = nxt && rest.match(/(?:\t|\s)[\s#{MARK_ON}#{MARK_OFF}]*\(?#{nxt}[.)]\s+|(?<=\S)[#{MARK_ON}#{MARK_OFF}]*\(?#{nxt}[.)]\s+(?=\S)/i)
        split = nil if split && split.begin(0).zero?
        text = split ? rest[0...split.begin(0)] : rest
        marked = "#{prefix}#{text}".match?(/[#{MARK_ON}#{MARK_OFF}]/) || unmark(text).strip.match?(/#{TICK}\z|\A#{TICK}/)
        current[:options] << unmark(text).sub(/#{TICK}\z/, "").sub(/\A#{TICK}/, "").strip
        current[:marks] << marked
        break unless split

        rest = rest[split.begin(0)..].lstrip
      end
    end

    def finish(current, questions)
      questions << current if current
    end

    def build_result(header, questions, passages, key)
      warnings = []
      built = questions.filter_map do |q|
        if q[:options].size < 2
          warnings << "Question #{q[:number]}: options (A, B, C…) not found — skipped"
          next
        end
        shared = passages.select { |p| q[:number].between?(*p[:range]) }.map { |p| p[:text] }
        body = (shared + q[:body]).join("\n").gsub(/\n{3,}/, "\n\n").strip
        letter = q[:answer] || key[q[:number]]
        index = letter ? Question::LETTERS.index(letter) : nil
        index = nil if index && index >= q[:options].size
        index ||= q[:marks].index(true) if q[:marks].count(true) == 1
        { body: body, options: q[:options], correct_index: index, marks: 1 }
      end
      raise Error, "No questions found. Number the questions (1. 2. 3.) and write options as A. B. C. D." if built.empty?

      text = header.join("\n")
      marks = text[/each question carries\s+(\d+)\s+marks?/i, 1].to_i
      built.each { |q| q[:marks] = marks } if marks.positive?
      Result.new(title: guess_title(header), duration: text[/duration\s*[:\-]?\s*(\d{1,3})\s*min/i, 1]&.to_i,
                 questions: built, warnings: warnings)
    end

    def guess_title(header)
      lines = header.map { |l| l.delete_prefix("• ").squish }.reject(&:blank?)
      lines.find { |l| l.length <= 80 && l.match?(/test|paper|exam|assessment|quiz/i) && !l.match?(/\A(total|type|duration|maximum|instructions?)\b/i) } ||
        lines.find { |l| l.length <= 80 }
    end

    def unmark(text)
      text.to_s.delete(MARK_ON).delete(MARK_OFF)
    end
end
