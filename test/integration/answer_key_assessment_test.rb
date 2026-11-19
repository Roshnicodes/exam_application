require "test_helper"

# A practical test with an answer key: HR uploads the key, the candidate answers on the answer
# sheet, it is marked on submit and HR can change any question's marks.
class AnswerKeyAssessmentTest < ActionDispatch::IntegrationTest
  KEY = <<~TXT
    Section | Type | Questions | Marks
    A | Objective (MCQ) | Q1 – Q2 | 2
    B | Descriptive | Q3 | 2
    C | Practical | Q4 | 4
    Q1 – (b) ₹500 late fee.
    Q2 – (c) Sec 16(4).
    Q3. Due dates of GSTR-1 and GSTR-3B (2 marks)
    GSTR-1 on the 11th, GSTR-3B on the 20th.
    Q4. TDS Computation (4 Marks)
    TDS on ₹80,000 = ₹8,000; rent TDS ₹21,000; total ₹29,000.
  TXT

  setup do
    @user = users(:one)
    @user.update!(name: "HR One")
  end

  test "HR uploads an answer key, the candidate's answers are marked and HR adjusts them" do
    sign_in_as @user
    post assessments_path, params: { assessment: {
      title: "Accounts paper", description: "GST and TDS questions", kind: "case_study", duration_minutes: 40,
      max_marks: 100, pass_percentage: 50, max_warnings: 5, require_upload: "1", allow_notes: "1", active: "1",
      files: [ fixture_file_upload("question_paper.docx", "application/vnd.openxmlformats-officedocument.wordprocessingml.document") ],
      answer_key: Rack::Test::UploadedFile.new(StringIO.new(KEY), "text/plain", original_filename: "key.txt")
    } }
    assessment = Assessment.order(:id).last
    assert_redirected_to assessment_path(assessment)
    assert_equal %w[q1 q2 q3 q4], assessment.answer_items.map { |i| i["id"] }
    assert_equal 8, assessment.max_marks # out of the key's total
    assert assessment.answer_key.attached?

    # each question's text (and the MCQ's options) is read from the question paper
    q1 = assessment.answer_items.find { |i| i["id"] == "q1" }
    assert_equal "Late fee for GSTR-3B?", q1["question"]
    assert_equal %w[250 500 750 Nil], q1["options"]
    assert_match "TDS Computation", assessment.answer_items.find { |i| i["id"] == "q4" }["question"]

    get assessment_path(assessment)
    assert_response :success
    assert_match "Save answer key", response.body

    # HR corrects Q2's answer
    patch answer_key_assessment_path(assessment), params: { items: {
      "0" => { id: "q2", kind: "choice", answer: "d", marks: "1" }
    } }
    assert_equal "D", assessment.reload.answer_items.find { |i| i["id"] == "q2" }["answer"]

    # the candidate
    invitation = @user.invitations.create!(candidate_name: "Asha Rao", candidate_phone: "9876500000", vacancy: "Accountant",
                                           assessment: assessment, interview_plan: "practical", max_warnings: 5)
    round = invitation.interview_rounds.sole
    token = invitation.token
    post exam_request_otp_path(token), params: { phone: "9876500000" }
    post exam_verify_otp_path(token), params: { otp: invitation.reload.otp_code }
    round.open!
    get exam_assessment_path(token)
    assert_match "answer sheet on the next screen", response.body
    post exam_assessment_start_path(token)

    get exam_assessment_path(token)
    assert_match "Your answer sheet", response.body
    assert_match "as_q1", response.body
    assert_match "qp-panel", response.body          # the paper stays open next to the answers
    assert_match "Full paper", response.body
    assert_match "Late fee for GSTR-3B?", response.body # the question above its options
    assert_match %(id="as_q1" class="input"), response.body # a box to type the answer — nothing to choose
    assert_no_match 'type="radio"', response.body
    assert_match "Review &amp; submit", response.body
    assert_no_match "Upload your finished work", response.body # nothing to upload: answers save by themselves
    assert_no_match "up-zone", response.body

    # the Word question paper opens inside the page
    paper = round.task_attachments.first
    get exam_assessment_task_preview_path(token, paper.id)
    assert_response :success
    assert_match "task-doc", response.body
    assert_match "TDS Computation", response.body

    # answers autosave (unknown question ids are ignored)
    patch exam_assessment_answers_path(token), params: { answers: {
      q1: "B", q2: "C", q3: "GSTR-1 by 11th and GSTR-3B by 20th", q4: "TDS 8,000 + 21,000 = 29,000", hack: "x"
    } }, as: :json
    assert_response :success
    assert_equal 4, JSON.parse(response.body)["answered"]
    assert_not round.reload.answers.key?("hack")

    post exam_assessment_submit_path(token)
    round.reload
    assert round.submitted?
    assert round.graded?
    assert_equal 1.0, round.item_marks["q1"]["marks"]  # right
    assert_equal 0.0, round.item_marks["q2"]["marks"]  # wrong (key says D)
    assert_equal 2.0, round.item_marks["q3"]["marks"]  # all key points
    assert_equal 4.0, round.item_marks["q4"]["marks"]
    assert_equal 7, round.marks                        # 7 of 8

    # HR changes Q3 and marks again from the key: HR's mark stays
    get room_invitation_interview_round_path(invitation, round)
    assert_response :success
    assert_match "Answer sheet · marked from the answer key", response.body
    post mark_items_invitation_interview_round_path(invitation, round), params: { marks: { q3: "1.5" } }
    assert_equal 6.5, round.reload.sheet_score
    post remark_invitation_interview_round_path(invitation, round)
    assert_equal 1.5, round.reload.item_marks["q3"]["marks"]
    assert_equal 7, round.marks # 6.5 of 8 -> 7 (rounded) out of 8
    assert_equal 7.0, round.auto_score # the application's own marks stay on record
    assert_equal [ "HR One" ], round.changed_by
    get room_invitation_interview_round_path(invitation, round)
    assert_match "Changed by", response.body

    # a department / thematic head gives their own marks on the panelist link
    post watch_marks_path(invitation.watch_token, round), params: { marks: { q4: "3" } }
    assert_equal 4.0, round.reload.item_marks["q4"]["marks"] # no name -> nothing saved
    post watch_marks_path(invitation.watch_token, round), params: { reviewer_name: "Head – Finance", marks: { q4: "3" } }
    round.reload
    assert_equal 3.0, round.item_marks["q4"]["marks"]
    assert_equal 4.0, round.item_marks["q4"]["auto"]
    assert_equal "Head – Finance", round.item_marks["q4"]["by"]
    assert_equal 5.5, round.sheet_score
    assert_equal 7.0, round.auto_score
    get watch_round_path(invitation.watch_token, round)
    assert_response :success
    assert_match "Marks saved by Head – Finance", response.body
    assert_match "Head – Finance", response.body
  end

  test "every task file reaches the candidate as uploaded" do
    sign_in_as @user
    post assessments_path, params: { assessment: {
      title: "Leaky paper", description: "x", kind: "case_study", duration_minutes: 30, max_marks: 10, pass_percentage: 50, max_warnings: 5,
      files: [ fixture_file_upload("question_paper.docx", "application/vnd.openxmlformats-officedocument.wordprocessingml.document"),
               Rack::Test::UploadedFile.new(StringIO.new(KEY.dup), "text/plain", original_filename: "Answer Key.txt") ],
      answer_key: Rack::Test::UploadedFile.new(StringIO.new(KEY.dup), "text/plain", original_filename: "key.txt")
    } }
    assessment = Assessment.order(:id).last
    assert_redirected_to assessment_path(assessment)

    invitation = @user.invitations.create!(candidate_name: "Ravi", candidate_phone: "9876500001", vacancy: "Accountant",
                                           assessment: assessment, interview_plan: "practical", max_warnings: 5)
    round = invitation.interview_rounds.sole
    assert_equal [ "question_paper.docx", "Answer Key.txt" ], round.task_attachments.map { |f| f.filename.to_s }
  end

  test "without an answer key a practical works as before: the file to read, an upload, no answer sheet" do
    sign_in_as @user
    paper = "Q1. Late fee for GSTR-3B?\n(a) 250\n(b) 500\nAnswer: (b)\nQ2. Explain the purpose of GSTR-1. (4 marks)\n"
    post assessments_path, params: { assessment: {
      title: "Paper only", description: "x", kind: "case_study", duration_minutes: 30, max_marks: 10, pass_percentage: 50, max_warnings: 5,
      require_upload: "1", allow_download: "1", active: "1",
      files: [ Rack::Test::UploadedFile.new(StringIO.new(paper), "text/plain", original_filename: "paper.txt") ]
    } }
    assessment = Assessment.order(:id).last
    assert_empty assessment.answer_items

    invitation = @user.invitations.create!(candidate_name: "Roshni", candidate_phone: "9876500002", vacancy: "Accountant",
                                           assessment: assessment, interview_plan: "practical", max_warnings: 5)
    round = invitation.interview_rounds.sole
    token = invitation.token
    post exam_request_otp_path(token), params: { phone: "9876500002" }
    post exam_verify_otp_path(token), params: { otp: invitation.reload.otp_code }
    round.open!
    post exam_assessment_start_path(token)
    get exam_assessment_path(token)
    assert_empty assessment.reload.answer_items
    assert_match "paper.txt", response.body                 # the whole file, as uploaded
    assert_match "disposition=attachment", response.body    # download allowed
    assert_match "Upload your finished work", response.body
    assert_no_match "Your answer sheet", response.body
  end

  test "an answer key the app can't read is a form error" do
    sign_in_as @user
    assert_no_difference "Assessment.count" do
      post assessments_path, params: { assessment: {
        title: "Bad key", description: "x", kind: "other", duration_minutes: 10, max_marks: 10, pass_percentage: 50, max_warnings: 5,
        answer_key: Rack::Test::UploadedFile.new(StringIO.new("nothing useful"), "text/plain", original_filename: "key.txt")
      } }
    end
    assert_response :unprocessable_entity
    assert_match "Answer key", response.body
  end
end
