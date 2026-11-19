# The answer key of a practical test, read from HR's Word / PDF / Excel / text file, and the
# marking of a candidate's answer sheet against it.
#
# Understands keys like "Accountant Assistant – Answer Key & Marking Scheme":
#   - MCQ answers from a key table ("1 | B | 6 | C …") or lines ("Q1 – (b) ₹500: …")
#   - written / numerical questions ("Q16. Purpose of GSTR-1 …", "Q21. GST Liability (6 Marks)")
#     with sub-parts that carry their own marks ("(a) Output tax liability (1.5 marks)")
#   - marks from the heading, "(2 marks each)" sections or the summary table ("A | MCQ | Q1 – Q15 | 15")
# Each item: { "id", "label", "title", "kind" (choice / number / text), "answer", "model", "terms", "marks" }
class AnswerKey
  class Error < StandardError; end

  KINDS = { "choice" => "Option (A–D)", "number" => "Number", "text" => "Written answer" }.freeze
  LETTERS = %w[A B C D E].freeze

  Q_HEAD = /\AQ\s?(\d{1,3})\s*[.)]\s+(.+)\z/i
  EXPLAIN = /\AQ\s?(\d{1,3})\s*[–—:-]\s*\(?([A-E])\)?(?=[\s:)]|\z)\s*[):]?\s*(.*)\z/i
  PART = /\A\(([a-z])\)\s*(\([ivx]+\))?\s*(.+)\z/i
  SECTION = /\ASection\s+([A-Z])\b\s*[:–—-]?\s*(.*)\z/i
  MARKS_IN = /\((\d+(?:\.\d+)?)\s*marks?\)/i
  EACH = /(\d+(?:\.\d+)?)\s*marks?\s*each/i
  RANGE = /Q\s?(\d+)\s*[–—-]\s*Q\s?(\d+)/i
  PARTS_RANGE = /Q\s?(\d+)\s*\(([a-z])\)\s*[–—-]\s*\(([a-z])\)/i

  def self.parse(file)
    new(QuestionPaperParser.new(file).lines).items
  rescue QuestionPaperParser::Error => e
    raise Error, e.message
  end

  def initialize(lines)
    @lines = Array(lines).map { |l| l.to_s.gsub(/[[:space:]]+/, " ").strip }.reject(&:empty?)
  end

  def items
    @mcq = {}
    @explain = {}
    @written = []
    @ranges = []
    @section_parent = {}
    read
    list = mcq_items + written_items
    raise Error, "No questions or answers were found in this file. Check that answers look like “Q1 – (b)” or a “Q | Ans” table, and written questions start with “Q16.”." if list.empty?

    assign_missing_marks(list)
    list
  end

  # ---------------------------------------------------------------- marking
  # => { "marks" => awarded, "max" => marks, "correct" => true/false/nil, "matched" => [...], "review" => bool }
  def self.mark(item, response)
    max = item["marks"].to_f
    given = response.to_s.strip
    return { "marks" => 0.0, "max" => max, "correct" => false, "review" => false, "blank" => true } if given.empty?

    case item["kind"]
    when "choice"
      ok = given.upcase == item["answer"].to_s.upcase
      { "marks" => ok ? max : 0.0, "max" => max, "correct" => ok, "review" => false }
    when "number"
      want = number(item["answer"])
      got = numbers(given).first
      ok = want && got && close?(got, want)
      { "marks" => ok ? max : 0.0, "max" => max, "correct" => !!ok, "review" => false }
    else
      terms = Array(item["terms"])
      return { "marks" => 0.0, "max" => max, "correct" => nil, "review" => true, "matched" => [] } if terms.empty?

      found = terms_in(given)
      matched = terms.select { |t| found.any? { |f| same_term?(t, f) } }
      share = [ matched.size / (terms.size * 0.7), 1.0 ].min # ~70% of the key points earns full marks
      { "marks" => ((max * share) * 2).round / 2.0, "max" => max, "correct" => nil, "review" => true, "matched" => matched }
    end
  end

  # Key points of a model answer: amounts, percentages, dates, sections / rules, form names.
  def self.terms_in(text)
    text = text.to_s
    terms = []
    text.scan(/₹\s?(\d[\d,]*(?:\.\d+)?)(\s*(?:lakh|lac|crore|cr)\b)?/i) do |amount, scale|
      value = number(amount).to_f * { "lakh" => 1e5, "lac" => 1e5, "crore" => 1e7, "cr" => 1e7 }.fetch(scale.to_s.strip.downcase, 1)
      terms << "n:#{num_s(value.to_s)}"
    end
    text.scan(/\b(\d{1,2})(?:st|nd|rd|th)\b/) { terms << "o:#{Regexp.last_match(1).to_i}" }
    text.scan(/(?<![\w.,\/(₹-])(\d{1,3}(?:,\d{2,3})+(?:\.\d+)?|\d{3,}(?:\.\d+)?)(?![\w%\/(-]|\s*(?:lakh|lac|crore|cr)\b)/i) do
      value = number(Regexp.last_match(1))
      terms << "n:#{num_s(Regexp.last_match(1))}" if value && value >= 100 && !(1990..2100).cover?(value)
    end
    text.scan(/(\d+(?:\.\d+)?)\s?%/) { terms << "p:#{Regexp.last_match(1).to_f}" }
    text.scan(/\b(\d{1,2})[-\/.](\d{1,2})[-\/.](\d{2,4})\b/) { |d, m, y| terms << "d:#{d.to_i}-#{m.to_i}-#{y.to_i % 100}" }
    text.scan(/\b(\d{2,3}[A-Z]?(?:-?[A-Z])?(?:\(\w{1,3}\))+)/) { terms << "s:#{Regexp.last_match(1).downcase.delete("-")}" }
    text.scan(/\b(19[2-6][A-Z]{1,2}|194-[A-Z])\b/) { terms << "s:#{Regexp.last_match(1).downcase.delete("-")}" }
    text.scan(/\b(GSTR-?\s?\d[A-Z]?|Form\s?\d+[A-Z]*|Rule\s?\d+[A-Z]*)\b/i) { terms << "f:#{Regexp.last_match(1).downcase.gsub(/[\s-]/, "")}" }
    terms.uniq
  end

  def self.same_term?(key, found)
    return key == found unless key.start_with?("n:") && found.start_with?("n:")

    close?(key.delete_prefix("n:").to_f, found.delete_prefix("n:").to_f)
  end

  def self.close?(a, b)
    (a - b).abs <= [ b.abs * 0.01, 1 ].max
  end

  def self.number(text)
    s = text.to_s.delete(",₹ ").strip
    s.match?(/\A-?\d+(\.\d+)?\z/) ? s.to_f : nil
  end

  def self.numbers(text)
    text.to_s.scan(/-?\d[\d,]*(?:\.\d+)?/).filter_map { |n| number(n) }
  end

  def self.num_s(text)
    n = number(text)
    n == n.to_i ? n.to_i.to_s : n.to_s
  end

  # Readable form of a key point for HR ("n:100000" -> "₹1,00,000")
  def self.term_label(term)
    kind, value = term.split(":", 2)
    case kind
    when "n" then "₹#{ActiveSupport::NumberHelper.number_to_delimited(value, delimiter_pattern: Spreadsheet::INDIAN_GROUPS)}"
    when "p" then "#{value.to_f == value.to_i ? value.to_i : value}%"
    when "d" then value.tr("-", "/")
    when "o" then "#{value}#{value.to_i.between?(11, 13) ? "th" : { 1 => "st", 2 => "nd", 3 => "rd" }.fetch(value.to_i % 10, "th")}"
    when "s" then "Sec #{value.upcase}"
    else value.upcase.sub(/\AGSTR/, "GSTR-").sub("--", "-")
    end
  end

  private
    def read
      section = nil
      section_each = nil
      current = nil
      q = nil
      close = -> { @written << current if current; current = nil }

      @lines.each do |line|
        next if line.match?(/\A(?:Q(?:\.?\s*No\.?)?\s+Ans(?:wer)?s?\s*)+\z/i) # "Q Ans Q Ans" (a key table's head, as a PDF gives it)

        words = line.split(/\s+/)
        next if words.size >= 2 && words.size.even? && !line.include?("|") && mcq_row(words) # "1 B 6 C 11 C" (a PDF's key table)

        cells = line.split(" | ").map(&:strip)
        if cells.size > 1
          next if mcq_row(cells) || summary_row(cells, section)

          current[:text] << line if current
          next
        end

        if (m = line.match(SECTION))
          close.()
          section = m[1].upcase
          section_each = line[EACH, 1]&.to_f
          q = nil
          @mcq_each ||= section_each if line.match?(/MCQ|objective/i)
        elsif (m = line.match(EXPLAIN))
          close.()
          @mcq[m[1].to_i] ||= m[2].upcase
          @explain[m[1].to_i] = m[3].sub(/\A[):\s]+/, "")
        elsif (m = line.match(Q_HEAD))
          close.()
          q = m[1].to_i
          current = { num: q, part: nil, title: clean_title(m[2]), marks: m[2][MARKS_IN, 1]&.to_f || section_each, text: [], section: section }
        elsif (m = line.match(PART)) && (q || @section_parent[section])
          close.()
          parent = q || @section_parent[section]
          current = { num: parent, part: m[1].downcase, title: clean_title(m[3]), marks: m[3][MARKS_IN, 1]&.to_f, text: [], section: section }
        elsif line.match?(/\AMarking\s*:/i)
          current[:rubric] = line.sub(/\AMarking\s*:\s*/i, "") if current
        elsif current
          current[:text] << line
        end
      end
      close.()
    end

    # "1 | B | 6 | C | 11 | C" (a Q / Ans key table)
    def mcq_row(cells)
      return false unless cells.size.even? && cells.each_slice(2).all? { |n, a| n.match?(/\AQ?\s?\d{1,3}\z/i) && a.match?(/\A\(?[A-E]\)?\z/i) }

      cells.each_slice(2) { |n, a| @mcq[n[/\d+/].to_i] = a.delete("()").upcase }
      true
    end

    # "A | Objective (MCQ) | Q1 – Q15 | 15" or "D | Case study | Q24 (a)–(d) | 10"
    def summary_row(cells, section)
      total = cells.last.to_s[/\A\d+(?:\.\d+)?\z/]&.to_f
      return false unless total

      joined = cells.join(" ")
      if (m = joined.match(PARTS_RANGE))
        @section_parent[cells.first.to_s.strip.upcase] = m[1].to_i if cells.first.to_s.match?(/\A[A-Z]\z/)
        @ranges << { from: m[1].to_i, to: m[1].to_i, total: total, parts: true }
        true
      elsif (m = joined.match(RANGE))
        @ranges << { from: m[1].to_i, to: m[2].to_i, total: total }
        true
      else
        false
      end
    end

    def clean_title(text)
      text.to_s.sub(MARKS_IN, "").sub(/[\s:–-]+\z/, "").strip.first(160)
    end

    def mcq_items
      @mcq.keys.sort.map do |n|
        { "id" => "q#{n}", "label" => "Q#{n}", "title" => "", "kind" => "choice", "answer" => @mcq[n],
          "model" => @explain[n].to_s.first(600), "terms" => [], "marks" => @mcq_each }
      end
    end

    # Questions with parts: the parts become the items when each part has its own marks.
    def written_items
      groups = @written.reject { |w| @mcq.key?(w[:num]) && w[:part].nil? && w[:text].empty? }.group_by { |w| w[:num] }
      groups.keys.sort.flat_map do |num|
        entries = groups[num]
        parent = entries.find { |e| e[:part].nil? }
        parts = entries.select { |e| e[:part] }
        if parts.any? && parts.all? { |p| p[:marks] }
          parts.map { |p| written_item(p, "q#{num}#{p[:part]}", "Q#{num} (#{p[:part]})") }
        else
          base = parent || parts.first.merge(part: nil)
          text = (parent ? parent[:text] : []) + parts.flat_map { |p| [ "(#{p[:part]}) #{p[:title]}" ] + p[:text] }
          [ written_item(base.merge(text: text, marks: base[:marks]), "q#{num}", "Q#{num}") ]
        end
      end
    end

    def written_item(entry, id, label)
      model = entry[:text].join("\n")
      { "id" => id, "label" => label, "title" => entry[:title].to_s, "kind" => "text", "answer" => nil,
        "model" => model.first(4000), "rubric" => entry[:rubric].to_s.first(600),
        "terms" => self.class.terms_in(model).first(14), "marks" => entry[:marks] }
    end

    # Marks not written next to a question: from the summary table ranges, else 1.
    def assign_missing_marks(list)
      @ranges.each do |range|
        members = list.select { |i| (range[:from]..range[:to]).cover?(i["id"][/\d+/].to_i) }
        next if members.empty?

        known = members.sum { |i| i["marks"].to_f }
        missing = members.reject { |i| i["marks"] }
        next if missing.empty?

        each = ((range[:total] - known) / missing.size)
        missing.each { |i| i["marks"] = each.positive? ? each.round(2) : 1.0 }
      end
      list.each { |i| i["marks"] = (i["marks"] || 1).to_f }
    end
end
