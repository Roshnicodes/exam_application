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

  # ---------------------------------------------------------------- what the candidate may see
  # A paper often carries its answers too ("Answer: B", an "Answer Key" section at the end,
  # "Q1 – (b) ₹500 …" lines). Returns the paper without them:
  #   { "lines" => [...], "removed" => true/false, "key_only" => true when nothing but answers is left }
  ANSWER_LINE = /\A\s*(?:correct\s+)?(?:ans(?:wer)?s?|solution|explanation|model\s+answer|working\s*notes?)\b\s*[:\-–—.)]/i
  # a heading after which everything is the key ("Answer Key & Marking Scheme", "Section D – Model answers")
  KEY_SECTION = /\A\s*(?:section\s+[a-z0-9]+\s*[:\-–—]\s*)?(?:[\w\/&()]+\s+){0,3}(?:answer\s*keys?|marking\s*scheme|key\s*answers?|model\s*answers?|answers?\s*(?:&|and)\s*(?:explanations?|solutions?))\b/i
  # a heading on its own ("Answers", "Solutions:"): answers follow until the next real question
  ANSWER_HEADING = /\A\s*(?:answers?|solutions?|explanations?)\s*:?\s*\z/i
  KEY_LINE = /\A\s*(?:Q\s?)?\d{1,3}\s*[.):–—-]\s*(?:\([A-Ea-e]\)(?:\s.*)?|[A-Ea-e](?:\s*[).:–—-].*)?)\z/
  KEY_PAIR = /\b\d{1,3}\s*[.):–—-]?\s*\(?[A-Ea-e]\)?(?![A-Za-z0-9])/
  QUESTION_LINE = /\A\s*(?:Q(?:uestion)?\.?\s*)?\d{1,3}\s*[.):–-]\s*\S/i

  def self.candidate_view(lines)
    kept = []
    removed = skipping = seen_question = key_style = false
    key_numbers = []
    Array(lines).map(&:to_s).each do |line|
      text = line.gsub(/[[:space:]]+/, " ").strip
      next kept << line if text.empty?

      if seen_question && text.length <= 100 && text.match?(KEY_SECTION) # the rest of the file is the key
        removed = true
        break
      elsif key_line?(text)
        removed = key_style = true
        key_numbers.concat(text.scan(/(?:\A|\s|\|)Q?\s?(\d{1,3})(?=\s*[.):–—|-]?\s*\(?[A-Ea-e]\)?(?![A-Za-z0-9]))/i).flatten.map(&:to_i))
      elsif text.match?(ANSWER_HEADING) || text.match?(ANSWER_LINE)
        removed = skipping = true
      elsif text.match?(QUESTION_LINE) || text.match?(/\ASection\s+[A-Z]\b/i)
        skipping = false
        seen_question ||= text.match?(QUESTION_LINE)
        kept << line
      elsif skipping
        # the rest of an answer / explanation
      else
        kept << line
      end
    end
    found = new(kept).questions.select { |id, q| id.match?(/\Aq\d+\z/) && q["text"].present? }
    asked = found.keys.map { |id| id[1..].to_i }
    # an answer key ("Q1 – (b) ₹500", a key table, model answers) is not a question paper: the
    # questions it answers are not written in it (a paper with its key has them, with options)
    key_only = removed && (found.empty? || (key_style && (key_numbers.any? ? (asked & key_numbers).empty? : found.values.none? { |q| Array(q["options"]).any? })))
    { "lines" => key_only ? [] : kept, "removed" => removed, "key_only" => key_only }
  end

  # "Q1 – (b) ₹500", "1. B", "1-B 2-C 3-A", or a row of an answer table ("1 | B | 6 | C", "Q | Ans")
  def self.key_line?(text)
    return false if text.scan(INLINE_OPTIONS).size >= 2 # a question with its options on one line

    return true if text.match?(KEY_LINE)
    return true if text.match?(/\A(?:Q(?:\.?\s*No\.?)?\s+Ans(?:wer)?s?\s*)+\z/i) # "Q Ans Q Ans" (a key table's head)

    words = text.split
    return true if !text.include?("|") && words.size >= 2 && words.size.even? &&
                   words.each_slice(2).all? { |n, l| n.match?(/\AQ?\d{1,3}\z/i) && l.match?(/\A\(?[A-Ea-e]\)?\z/) } # "1 B 6 C 11 C"
    return true if text.scan(KEY_PAIR).size >= 3 && text.gsub(KEY_PAIR, "").gsub(/[\s,;|]/, "").length < 6
    return false unless text.include?("|")

    cells = text.split("|").map(&:strip).reject(&:empty?)
    return false unless cells.size >= 2 && cells.size.even?

    # "Q | Ans | Q | Ans" or "1 | B | 6 | C" — (number, letter) pairs; a data table ("A | 185") is not one
    cells.each_slice(2).all? { |q, a| q.match?(/\AQ(?:\.?\s*No\.?)?\z/i) && a.match?(/\AAns(?:wer)?s?\z/i) } ||
      cells.each_slice(2).all? { |n, l| n.match?(/\AQ?\s?\d{1,3}\z/i) && l.match?(/\A\(?[A-Ea-e]\)?\z/) }
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
        elsif entry["options"].empty? && line.match?(/\AA\s*[.)]\s+\S/) && line.scan(/(?:\A|\s)[A-E]\s*[.)]\s+/).size >= 2
          # "A. ₹250   B. ₹500   C. ₹750" — the options on one line
          entry["options"].concat(line.split(/(?:\A|\s+)[A-E]\s*[.)]\s+/).map(&:strip).reject(&:empty?).first(5))
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
