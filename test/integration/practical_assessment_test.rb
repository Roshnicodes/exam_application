require "test_helper"

# End to end: HR creates a practical assessment, gives it to a candidate (on its own and
# together with the MCQ test), the candidate works on it under proctoring and HR marks it.
class PracticalAssessmentTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @user.update!(name: "HR One")
    @assessment = @user.assessments.create!(title: "Excel practical test", description: "Pivot table on sales data", kind: "excel", duration_minutes: 30,
                                            max_marks: 50, pass_percentage: 50, instructions: "Make a pivot table",
                                            online_sheet: false) # the download / upload way (see sheet_assessment_test for the built-in sheet)
    @assessment.files.attach(io: StringIO.new("a,b\n1,2\n"), filename: "sales.csv", content_type: "text/csv")
    @quiz = @user.quizzes.create!(title: "General aptitude", duration_minutes: 20, pass_percentage: 50,
                                  questions_attributes: [ { body: "2+2?", options: [ "3", "4" ], correct_index: 1, marks: 1 } ])
  end

  test "HR manages practical assessments" do
    sign_in_as @user
    get assessments_path
    assert_response :success
    assert_match "Excel practical test", response.body

    get new_assessment_path
    assert_response :success

    assert_difference "Assessment.count" do
      post assessments_path, params: { assessment: { title: "Tally entry test", kind: "tally", description: "Sales entries in Tally", duration_minutes: 45,
                                                     max_marks: 100, pass_percentage: 60, max_warnings: 5,
                                                     instructions: "Pass the sales entries", require_upload: "1", allow_download: "1",
                                                     allow_notes: "1", active: "1", allow_app_switch: "1",
                                                     files: [ fixture_file_upload("task.txt", "text/plain") ] } }
    end
    created = Assessment.order(:id).last
    assert_equal "Sales entries in Tally", created.description

    # a practical test needs its short description
    assert_no_difference "Assessment.count" do
      post assessments_path, params: { assessment: { title: "No description", kind: "excel", duration_minutes: 30, max_marks: 10,
                                                     pass_percentage: 50, max_warnings: 5 } }
    end
    assert_response :unprocessable_entity
    assert_match "short description", response.body
    assert_equal "tally", created.kind
    assert created.allow_app_switch?
    assert_equal 1, created.files.size

    get assessment_path(@assessment)
    assert_response :success
    get edit_assessment_path(@assessment)
    assert_response :success

    patch assessment_path(@assessment), params: { assessment: { title: "Excel practical test v2", duration_minutes: 40 } }
    assert_redirected_to assessment_path(@assessment)
    assert_equal 40, @assessment.reload.duration_minutes
  end

  test "practical-only invitation needs no question paper and builds one assessment round" do
    sign_in_as @user
    assert_difference "Invitation.count" do
      post invitations_path, params: { invitation: { candidate_name: "Asha Rao", vacancy: "Accountant",
                                                     interview_plan: "practical", assessment_id: @assessment.id,
                                                     max_warnings: 5, language: "en" } }
    end
    invitation = Invitation.order(:id).last
    assert_nil invitation.quiz_id
    assert_not invitation.test_required?
    round = invitation.interview_rounds.sole
    assert round.assessment?
    assert_equal @assessment.duration_minutes, round.duration
    assert_equal @assessment.max_marks, round.total_marks

    get invitation_path(invitation)
    assert_response :success
    assert_match "Excel practical test", response.body
  end

  test "HR adds a practical assessment round with its own file to an existing candidate" do
    sign_in_as @user
    invitation = create_invitation(plan: "separate")
    assert_difference "invitation.interview_rounds.count" do
      post invitation_interview_rounds_path(invitation), params: {
        interview_round: { kind: "assessment", name: "Tally test for Asha", duration_minutes: 20, max_marks: 25,
                           instructions: "Pass these entries", allow_app_switch: "1",
                           task_files: [ fixture_file_upload("task.txt", "text/plain") ] }
      }
    end
    round = invitation.interview_rounds.reload.find(&:assessment?)
    assert_equal 20, round.duration
    assert_equal 25, round.total_marks
    assert round.allow_app_switch?
    assert_equal 1, round.task_attachments.size

    get room_invitation_interview_round_path(invitation, round)
    assert_response :success
    assert_match "Tally test for Asha", response.body
  end

  test "candidate does the practical assessment with proctoring and HR marks it" do
    invitation = create_invitation(plan: "practical", assessment: @assessment)
    round = invitation.interview_rounds.sole
    token = invitation.token

    # verify by OTP
    get exam_path(token)
    assert_response :success
    post exam_request_otp_path(token), params: { phone: "9876500000" }
    post exam_verify_otp_path(token), params: { otp: invitation.reload.otp_code }
    assert_redirected_to exam_assessment_path(token)

    # nothing open yet: the waiting screen
    get exam_assessment_path(token)
    assert_response :success
    assert_match "Waiting for HR", response.body

    # HR opens the round
    round.open!

    get exam_assessment_path(token)
    assert_response :success
    assert_match "Camera &amp; system check", response.body

    post exam_assessment_start_path(token)
    assert_redirected_to exam_assessment_path(token)
    assert round.reload.working?

    get exam_assessment_path(token)
    assert_response :success
    assert_match "Upload your finished work", response.body
    assert_match "Make a pivot table", response.body

    # a warning while working is logged against the round
    post exam_events_path(token), params: { kind: "tab_switch", round_id: round.id }
    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "assessment", body["status"]
    assert_equal 1, body["warnings"]
    assert_not body["terminated"]
    assert_equal 1, invitation.proctor_events.for_round(round).violations.count

    # typed answer + file upload
    patch exam_assessment_notes_path(token), params: { notes: "Used VLOOKUP" }
    assert_response :success
    post exam_assessment_files_path(token), params: { files: [ fixture_file_upload("task.txt", "text/plain") ] }
    assert_response :success
    assert JSON.parse(response.body)["ok"]
    assert_equal 1, round.reload.submissions.size

    # a file type that is not allowed is refused
    post exam_assessment_files_path(token), params: { files: [ fixture_file_upload("blocked.exe", "application/octet-stream") ] }
    assert_response :success
    refused = JSON.parse(response.body)
    assert_not refused["ok"]
    assert_equal 1, round.reload.submissions.size

    # submit
    post exam_assessment_submit_path(token), params: { notes: "Used VLOOKUP and a pivot" }
    assert_redirected_to exam_assessment_path(token)
    round.reload
    assert round.submitted?
    assert_equal "completed", round.status
    assert_equal "Used VLOOKUP and a pivot", round.candidate_notes

    get exam_assessment_path(token)
    assert_response :success
    assert_match "Submitted", response.body

    # HR marks it
    sign_in_as @user
    post grade_invitation_interview_round_path(invitation, round), params: { marks: 40, grade_note: "Pivot correct" }
    assert_redirected_to room_invitation_interview_round_path(invitation, round)
    round.reload
    assert_equal 40, round.marks
    assert_equal 80, round.percentage
    assert round.passed?

    get room_invitation_interview_round_path(invitation, round)
    assert_response :success
    assert_match "task.txt", response.body
  end

  test "warning limit submits the practical assessment by itself" do
    invitation = create_invitation(plan: "practical", assessment: @assessment)
    round = invitation.interview_rounds.sole
    round.update!(max_warnings: 2)
    round.open!
    round.start_work!
    token = invitation.token
    post exam_request_otp_path(token), params: { phone: "9876500000" }
    post exam_verify_otp_path(token), params: { otp: invitation.reload.otp_code }

    post exam_events_path(token), params: { kind: "tab_switch", round_id: round.id }
    travel 10.seconds
    post exam_events_path(token), params: { kind: "multiple_faces", round_id: round.id }
    body = JSON.parse(response.body)
    assert body["terminated"]
    assert_equal exam_assessment_path(token), body["redirect"]
    assert round.reload.submitted?
    assert_match "Warning limit", round.termination_reason
  end

  test "time over submits the practical assessment" do
    invitation = create_invitation(plan: "practical", assessment: @assessment)
    round = invitation.interview_rounds.sole
    round.open!
    round.start_work!
    travel (@assessment.duration_minutes + 5).minutes
    InterviewRound.submit_overdue_work!
    assert round.reload.submitted?
    assert_equal "time_up", round.termination_reason
  end

  test "the MCQ test flow still works and a practical round waits for it" do
    invitation = create_invitation(plan: "separate", assessment: @assessment)
    token = invitation.token
    assert invitation.test_required?
    assert_equal %w[assessment interview interview], invitation.interview_rounds.map(&:kind)

    post exam_request_otp_path(token), params: { phone: "9876500000" }
    post exam_verify_otp_path(token), params: { otp: invitation.reload.otp_code }
    assert_redirected_to exam_instructions_path(token)
    get exam_instructions_path(token)
    assert_response :success
    post exam_start_path(token)
    assert_redirected_to exam_take_path(token)
    get exam_take_path(token)
    assert_response :success

    # a warning during the test still counts against the test, not a round
    post exam_events_path(token), params: { kind: "tab_switch" }
    assert_equal 1, invitation.reload.warnings_count

    question = @quiz.questions.first
    post exam_submit_path(token), params: { answers: { question.id.to_s => "1" } }
    assert_redirected_to exam_finished_path(token)
    assert invitation.reload.submitted?
    assert_equal 1, invitation.score

    # the practical round is offered on the finished page once HR opens it
    get exam_finished_path(token)
    assert_response :success
    invitation.interview_rounds.find(&:assessment?).open!
    get exam_finished_path(token)
    assert_match "Excel practical test", response.body
  end

  test "live monitor lists a practical assessment in progress" do
    invitation = create_invitation(plan: "practical", assessment: @assessment)
    round = invitation.interview_rounds.sole
    round.open!
    round.start_work!
    sign_in_as @user
    get live_monitor_path
    assert_response :success
    assert_match "Practical assessments live now", response.body
    assert_match invitation.candidate_name, response.body
  end

  test "panelist watch link shows the practical assessment read-only" do
    invitation = create_invitation(plan: "practical", assessment: @assessment)
    round = invitation.interview_rounds.sole
    round.open!
    round.start_work!
    round.submissions.attach(io: StringIO.new("x"), filename: "answer.xlsx",
                             content_type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")
    get watch_round_path(invitation.watch_token, round)
    assert_response :success
    assert_match "Candidate's work", response.body
    assert_match "answer.xlsx", response.body
    assert_no_match "Save marks", response.body
  end

  test "candidate views the task sheet inside the page, and HR can allow app switching on the assessment" do
    @assessment.update!(allow_app_switch: true)
    invitation = create_invitation(plan: "practical", assessment: @assessment)
    round = invitation.interview_rounds.sole
    token = invitation.token
    file = @assessment.files.attachments.sole

    post exam_request_otp_path(token), params: { phone: "9876500000" }
    post exam_verify_otp_path(token), params: { otp: invitation.reload.otp_code }

    # not working on the task yet: no preview
    get exam_assessment_task_preview_path(token, file.id)
    assert_response :not_found

    round.open!
    post exam_assessment_start_path(token)
    get exam_assessment_path(token)
    assert_match "assessment#preview", response.body
    assert_no_match "target=\"_blank\"", response.body
    assert_match "You may open", response.body

    get exam_assessment_task_preview_path(token, file.id)
    assert_response :success
    assert_select "table td", text: "a"
    assert_select "table td", text: "2"

    # someone else's file id is not served
    get exam_assessment_task_preview_path(token, 0)
    assert_response :not_found
  end

  test "new assessment form offers app switching, on by default" do
    sign_in_as @user
    get new_assessment_path
    assert_select "input[type=checkbox][name='assessment[allow_app_switch]'][checked]"
  end

  private
    def create_invitation(plan:, assessment: nil)
      @user.invitations.create!(candidate_name: "Asha Rao", candidate_phone: "9876500000", vacancy: "Accountant",
                                quiz: (plan == "practical" ? nil : @quiz), assessment: assessment,
                                interview_plan: plan, max_warnings: 5)
    end
end
