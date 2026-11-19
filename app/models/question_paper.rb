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
  KEY_SECTION = /\A\s*(?:section\s+[a-z0-9]+\s*[:\-–—]\s*)?(?:answer\s*keys?|marking\s*scheme|key\s*answers?|model\s*answers?|answers?\s*(?:&|and)\s*(?:explanations?|solutions?))\b/i
  # a heading on its own ("Answers", "Solutions:"): answers follow until the next real question
  ANSWER_HEADING = /\A\s*(?:answers?|solutions?|explanations?)\s*:?\s*\z/i
  KEY_LINE = /\A\s*(?:Q\s?)?\d{1,3}\s*[.):–—-]\s*(?:\([A-Ea-e]\)(?:\s.*)?|[A-Ea-e](?:\s*[).:–—-].*)?)\z/
  KEY_PAIR = /\b\d{1,3}\s*[.):–—-]?\s*\(?[A-Ea-e]\)?(?![A-Za-z0-9])/
  KEY_CELL = /\A\s*(?:Q\s?\d{1,3}|\d{1,3}|\(?[A-Ea-e]\)?|ans(?:wer)?s?|q\.?\s*(?:no\.?)?|key)\s*\z/i
  QUESTION_LINE = /\A\s*(?:Q(?:uestion)?\.?\s*)?\d{1,3}\s*[.):–-]\s*\S/i

  def self.candidate_view(lines)
    kept = []
    removed = skipping = seen_question = key_style = false
    Array(lines).map(&:to_s).each do |line|
      text = line.gsub(/[[:space:]]+/, " ").strip
      next kept << line if text.empty?

      if seen_question && text.length <= 100 && text.match?(KEY_SECTION) # the rest of the file is the key
        removed = true
        break
      elsif key_line?(text)
        removed = key_style = true
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
    questions = new(kept).values_of_questions
    # an answer key ("Q1 – (b) ₹500" and model answers, no options anywhere) is not a question paper
    key_only = removed && (questions.none? { |q| q["text"].present? } || (key_style && questions.none? { |q| Array(q["options"]).any? }))
    { "lines" => key_only ? [] : kept, "removed" => removed, "key_only" => key_only }
  end

  # The answers written in a paper that carries them: { "q1" => { "letter" => "B", "text" => "…" } }
  ANSWER_LETTER = /\A\s*(?:correct\s+)?(?:ans(?:wer)?s?|key|correct\s+option)\s*[:\-–.]?\s*\(?([A-Ea-e])\)?(?![A-Za-z0-9])/i

  def self.answers_in(lines)
    found = Hash.new { |h, k| h[k] = { "text" => +"" } }
    current = nil
    collecting = in_key = false
    Array(lines).each do |line|
      text = line.to_s.gsub(/[[:space:]]+/, " ").strip
      next if text.empty?

      if text.length <= 100 && text.match?(KEY_SECTION)
        in_key = true
        collecting = false
      elsif key_line?(text)
        text.scan(/(?:\A|\s|\|)Q?\s?(\d{1,3})\s*[.):–—|-]?\s*\(?([A-Ea-e])\)?(?![A-Za-z0-9])/i) { |n, l| found["q#{n.to_i}"]["letter"] ||= l.upcase }
        cells = text.split("|").map(&:strip).reject(&:empty?)
        cells.each_slice(2) { |n, l| found["q#{n[/\d+/].to_i}"]["letter"] ||= l.delete("()").upcase if n.to_s.match?(/\d/) && l.to_s.match?(/\A\(?[A-Ea-e]\)?\z/) } if cells.size >= 2
      elsif !in_key && (m = text.match(QUESTION_LINE)) && (n = text[/\d{1,3}/].to_i)
        current = "q#{n}"
        collecting = false
      elsif current && (text.match?(ANSWER_LINE) || text.match?(ANSWER_HEADING))
        collecting = true
        found[current]["letter"] ||= text[ANSWER_LETTER, 1]&.upcase
        found[current]["text"] << text.sub(/\A\s*(?:correct\s+)?(?:ans(?:wer)?s?|solution|explanation|model\s+answer|working\s*notes?)\b\s*[:\-–—.)]?\s*/i, "") << "\n"
      elsif collecting && current
        found[current]["text"] << text << "\n"
      end
    end
    found.transform_values { |v| v.merge("text" => v["text"].strip) }
  end

  # "Q1 – (b) ₹500", "1. B", "1-B 2-C 3-A", or a row of an answer table ("1 | B | 6 | C", "Q | Ans")
  def self.key_line?(text)
    return false if text.scan(INLINE_OPTIONS).size >= 2 # a question with its options on one line

    return true if text.match?(KEY_LINE)
    return true if text.scan(KEY_PAIR).size >= 3 && text.gsub(KEY_PAIR, "").gsub(/[\s,;|]/, "").length < 6
    return false unless text.include?("|")

    cells = text.split("|").map(&:strip).reject(&:empty?)
    cells.size >= 2 && cells.all? { |c| c.match?(KEY_CELL) } && cells.any? { |c| c.match?(/\A\(?[A-Ea-e]\)?\z|\Aans/i) }
  end

  def initialize(lines)
    @lines = Array(lines).map { |l| l.to_s.gsub(/[[:space:]]+/, " ").strip }.reject(&:empty?)
    @q_prefixed = @lines.any? { |l| l.match?(/\AQ(?:uestion)?\.?\s*\d{1,3}\b/i) }
  end

  def values_of_questions
    questions.values
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
