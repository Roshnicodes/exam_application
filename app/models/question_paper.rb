# Splits a practical test's question paper (Word / PDF / text) into its questions, so the
# candidate's answer sheet can show each question with its options right above the answer:
#   { "q1" => { "text" => "Late fee for …", "options" => ["₹250", "₹500", …] },
#     "q21" => { "text" => "…" }, "q21a" => { "text" => "(a) Output tax liability" } }
class QuestionPaper
  Q_START = /\A(?:Q(?:uestion)?\.?\s*)(\d{1,3})\s*[.):–-]?\s*(.*)\z/i
  N_START = /\A(\d{1,3})\s*[.)]\s+(.+)\z/
  OPTION = /\A\(?([a-eA-E])\s*[).]\s+(.+)\z/
  PART = /\A\(([a-z])\)\s*(.+)\z/
  INLINE_OPTIONS = /\(\s*([a-dA-D])\s*\)\s*/

  def self.extract(lines)
    new(lines).questions
  end

  def initialize(lines)
    @lines = Array(lines).map { |l| l.to_s.gsub(/[[:space:]]+/, " ").strip }.reject(&:empty?)
    @q_prefixed = @lines.any? { |l| l.match?(/\AQ(?:uestion)?\.?\s*\d{1,3}\b/i) }
  end

  def questions
    found = {}
    current = nil
    @lines.each do |line|
      if line.match?(/\ASection\s+[A-Z]\b/i) # a new section: the previous question has ended
        current = nil
        @part = nil
      elsif (start = question_start(line, current))
        number, rest = start
        current = number
        entry = (found["q#{number}"] ||= { "text" => +"", "options" => [] })
        add_question_text(entry, rest)
      elsif current
        entry = found["q#{current}"]
        if entry["options"].empty? && line.scan(INLINE_OPTIONS).size >= 2 && line.match?(/\A\(\s*a\s*\)/i)
          add_question_text(entry, " #{line}")
        elsif (m = line.match(OPTION)) && entry["options"].size < 5 && m[1].upcase == ("A".ord + entry["options"].size).chr && !line.match?(PART_WITH_MARKS)
          entry["options"] << m[2].strip
        elsif (m = line.match(PART))
          (found["q#{current}#{m[1]}"] ||= { "text" => +"" })["text"] << line
          append(entry, line)
          @part = "q#{current}#{m[1]}"
        else
          append(entry, line)
          (found[@part]["text"] << "\n" << line) if @part && found[@part] && !line.match?(OPTION)
        end
      end
    end
    found.each_value { |e| e["text"] = e["text"].strip.first(4000) }
    found
  end

  PART_WITH_MARKS = /\(\d+(\.\d+)?\s*marks?\)/i

  private
    def question_start(line, current)
      m = @q_prefixed ? line.match(Q_START) : line.match(N_START)
      return unless m

      number = m[1].to_i
      return if current && !@q_prefixed && !(number > current && number <= current + 5)

      @part = nil
      [ number, m[2].to_s ]
    end

    # "Late fee? (a) 250 (b) 500 (c) 750 (d) Nil" -> question + options
    def add_question_text(entry, rest)
      pieces = rest.split(INLINE_OPTIONS)
      if pieces.size >= 5 # text, a, opt, b, opt, …
        entry["text"] << pieces.first.to_s.strip
        pieces.drop(1).each_slice(2) { |_letter, option| entry["options"] << option.to_s.strip if option.present? }
      else
        entry["text"] << rest
      end
    end

    def append(entry, line)
      entry["text"] << "\n" << line
    end
end
