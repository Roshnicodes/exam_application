require "test_helper"

# Reading answer keys / marking schemes (the format HR uses for practical papers) and marking answers.
class AnswerKeyTest < ActiveSupport::TestCase
  LINES = [
    "Clerk Test – Answer Key & Marking Scheme",
    "Section | Type | Questions | Marks",
    "A | Objective (MCQ) | Q1 – Q4 | 4",
    "B | Short descriptive | Q5 – Q6 | 4",
    "C | Practical | Q7 | 5",
    "D | Case study | Q8 (a)–(b) | 4",
    "Explanations:",
    "Q1 – (b) ₹500: 10 days × ₹50.",
    "Q2 – (c): Sec 16(4) limit.",
    "Section B: Model Answers (2 marks each)",
    "Q5. Due dates of GSTR-1 and GSTR-3B.",
    "• GSTR-1 is due on the 11th; GSTR-3B on the 20th.",
    "Marking: 1 for each date.",
    "Q6. Late fee for TDS returns.",
    "• ₹200 per day under Sec 234E, capped at the TDS amount.",
    "Section C: Solutions",
    "Q7. TDS Computation (5 Marks)",
    "(a) Professional fees (3 marks)",
    "TDS 10% on ₹80,000 = ₹8,000",
    "(b) Rent (2 marks)",
    "₹7,000 per month × 3 = ₹21,000",
    "Section D: Case Study Solution (4 Marks)",
    "(a) Issue 1 – Late return (2 marks)",
    "Interest = ₹2,40,000 × 18% × 20/365 = ₹2,367",
    "(b) Issue 2 – Cash payment (2 marks)",
    "Sec 40A(3): payments above ₹10,000 in cash are disallowed.",
    "Section A: MCQ Answer Key (1 mark each)",
    "Q | Ans | Q | Ans",
    "1 | B | 3 | A",
    "2 | C | 4 | D"
  ].freeze

  test "reads MCQs, written questions, parts and marks" do
    items = AnswerKey.new(LINES).items
    by_id = items.index_by { |i| i["id"] }

    assert_equal %w[q1 q2 q3 q4 q5 q6 q7a q7b q8a q8b], items.map { |i| i["id"] }
    assert_equal %w[B C A D], %w[q1 q2 q3 q4].map { |id| by_id[id]["answer"] }
    assert_equal "choice", by_id["q1"]["kind"]
    assert_equal 1.0, by_id["q1"]["marks"]
    assert_equal 2.0, by_id["q5"]["marks"]                 # "(2 marks each)"
    assert_equal [ 3.0, 2.0 ], [ by_id["q7a"]["marks"], by_id["q7b"]["marks"] ]
    assert_equal "Q8 (a)", by_id["q8a"]["label"]           # case-study parts belong to Q8 (summary table)
    assert_equal 17.0, items.sum { |i| i["marks"] }
    assert_includes by_id["q7a"]["terms"], "n:8000"
    assert_includes by_id["q5"]["terms"], "o:11"
    assert_includes by_id["q8b"]["terms"], "s:40a(3)"
    assert_equal "1 for each date.", by_id["q5"]["rubric"]
  end

  test "marks options, numbers and written answers" do
    choice = { "kind" => "choice", "answer" => "B", "marks" => 1 }
    assert_equal 1.0, AnswerKey.mark(choice, "b")["marks"]
    assert_equal 0.0, AnswerKey.mark(choice, "C")["marks"]
    assert AnswerKey.mark(choice, "")["blank"]

    number = { "kind" => "number", "answer" => "30700", "marks" => 2 }
    assert_equal 2.0, AnswerKey.mark(number, "₹30,700")["marks"]
    assert_equal 2.0, AnswerKey.mark(number, "30690")["marks"] # within 1%
    assert_equal 0.0, AnswerKey.mark(number, "25000")["marks"]

    written = { "kind" => "text", "marks" => 2, "terms" => AnswerKey.terms_in("₹2,40,000 × 18% × 20/365 = ₹2,367") }
    full = AnswerKey.mark(written, "Interest on 240000 @ 18% for 20 days = Rs 2367")
    assert_equal 2.0, full["marks"]
    assert full["review"]
    part = AnswerKey.mark(written, "Interest is 2367")
    assert_operator part["marks"], :<, 2.0
    assert_operator part["marks"], :>, 0.0
  end

  test "a file with nothing usable is rejected" do
    assert_raises(AnswerKey::Error) { AnswerKey.new([ "Just a title", "No answers here" ]).items }
  end
  test "a PDF's key table (spaces, not cells) is read" do
    pdf = [ "Section A: MCQ Answer Key (1 mark each)", "Q Ans Q Ans Q Ans", "1 B 6 C 11 C", "2 B 7 B 12 B", "5 B 10 C 15 B", "*** End of Answer Key ***" ]
    items = AnswerKey.new(pdf).items
    assert_equal %w[q1 q2 q5 q6 q7 q10 q11 q12 q15], items.map { |i| i["id"] }
    assert_equal %w[B C C], items.values_at(0, 3, 6).map { |i| i["answer"] }
    assert items.all? { |i| i["marks"] == 1.0 && i["kind"] == "choice" }
  end

  test "the candidate sees a paper without the answer key at its end; a key alone is never shown" do
    paper = [ "Accountant Assistant Test Paper – Answer Key", "Section A: MCQ (1 mark each)",
              "Q1. Late fee for GSTR-3B?", "A. ₹250   B. ₹500   C. ₹750   D. Nil", "Q2. ITC time limit?", "(a) Sec 16(4)", "(b) Sec 17",
              "Section B: Descriptive", "Q3. Explain GSTR-1. (2 marks)",
              "Section A: MCQ Answer Key (1 mark each)", "Q | Ans | Q | Ans", "1 | B | 2 | A", "Model answers", "Q3. GSTR-1 is the return of outward supplies." ]
    view = QuestionPaper.candidate_view(paper)
    assert view["removed"]
    assert_not view["key_only"]
    assert_equal "Q3. Explain GSTR-1. (2 marks)", view["lines"].last
    assert_equal %w[₹250 ₹500 ₹750 Nil], QuestionPaper.extract(view["lines"])["q1"]["options"]

    key = [ "Section A: MCQ Answer Key (1 mark each)", "Q Ans Q Ans", "1 B 6 C", "Q16. Purpose of GSTR-1 (2 marks)", "Outward supplies, by the 11th." ]
    assert QuestionPaper.candidate_view(key)["key_only"]
    assert_empty QuestionPaper.candidate_view(key)["lines"]
  end
  test "a data table in a question is not mistaken for an answer key" do
    paper = [ "3. The number of farmers covered by four field teams is:", "Team | Farmers", "A | 185", "B | 240",
              "What is the combined coverage?", "A. 700", "B. 715" ]
    view = QuestionPaper.candidate_view(paper)
    assert_not view["removed"]
    assert_equal paper, view["lines"]
  end
  test "a typed MCQ answer is read as its option" do
    item = { "kind" => "choice", "answer" => "B", "marks" => 1, "options" => [ "₹250", "₹500", "₹750", "Nil" ] }
    [ "B", "b", "(b)", "b) ₹500", "Option B", "Answer: B", "₹500", "Rs. 500", "500" ].each do |typed|
      assert_equal 1.0, AnswerKey.mark(item, typed)["marks"], typed
    end
    assert_equal({ "marks" => 0.0, "max" => 1.0, "correct" => false, "review" => false }, AnswerKey.mark(item, "a"))
    assert AnswerKey.mark(item, "a late fee of 500")["review"] # can't tell: HR checks it
  end
end
