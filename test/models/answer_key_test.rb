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
end
