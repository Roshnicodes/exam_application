require "test_helper"

# Every HR page still renders when a candidate was invited for a practical assessment only
# (so there is no MCQ question paper on the invitation).
class PracticalAssessmentPagesTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @user.update!(name: "HR One")
    @assessment = @user.assessments.create!(title: "Tally entry test", description: "Sales entries in Tally", kind: "tally", duration_minutes: 25, max_marks: 40)
    @assessment.files.attach(io: StringIO.new("entries"), filename: "entries.xlsx",
                             content_type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")
    @invitation = @user.invitations.create!(candidate_name: "Vikram Singh", candidate_phone: "9876511111",
                                            vacancy: "Accounts Executive", interview_plan: "practical",
                                            assessment: @assessment, max_warnings: 5)
    @round = @invitation.interview_rounds.sole
    sign_in_as @user
  end

  test "HR pages render for a practical-only candidate" do
    [ root_path, invitations_path, invitation_path(@invitation), edit_invitation_path(@invitation),
      report_invitation_path(@invitation), pipeline_path, schedule_path, results_path, live_monitor_path,
      completed_monitor_path, assessments_path, assessment_path(@assessment),
      room_invitation_interview_round_path(@invitation, @round), watch_path(@invitation.watch_token),
      new_invitation_path(plan: "practical", assessment_id: @assessment.id) ].each do |path|
      get path
      assert_response :success, "#{path} did not render"
    end
  end

  test "the printable PDF report and the Excel exports work without a question paper" do
    get pdf_invitation_path(@invitation)
    assert_response :success

    get export_invitations_path
    assert_response :success
    assert_equal "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", response.media_type

    get export_invitation_path(@invitation)
    assert_response :success
  end

  test "a practical assessment can be duplicated, re-opened and its round file removed" do
    assert_difference "Assessment.count" do
      post duplicate_assessment_path(@assessment)
    end
    copy = Assessment.order(:id).last
    assert_equal "Tally entry test (copy)", copy.title
    assert_equal 1, copy.files.size

    @round.open!
    @round.start_work!
    @round.submit_work!
    post reopen_invitation_interview_round_path(@invitation, @round)
    assert_redirected_to room_invitation_interview_round_path(@invitation, @round)
    @round.reload
    assert_not @round.submitted?
    assert_nil @round.work_started_at
    assert @round.open?

    @round.task_files.attach(io: StringIO.new("x"), filename: "own.xlsx", content_type: "application/vnd.ms-excel")
    file_id = @round.task_files.attachments.first.id
    delete task_file_invitation_interview_round_path(@invitation, @round, file_id: file_id)
    assert_equal 0, @round.reload.task_files.size
  end

  test "HR ending a live practical assessment saves the candidate's work" do
    @round.open!
    @round.start_work!
    @round.submissions.attach(io: StringIO.new("half done"), filename: "half.xlsx", content_type: "application/vnd.ms-excel")

    post complete_invitation_interview_round_path(@invitation, @round)
    assert_redirected_to room_invitation_interview_round_path(@invitation, @round)
    @round.reload
    assert @round.submitted?
    assert_equal 1, @round.submissions.size
    assert_match "Ended by HR", @round.termination_reason
  end

  test "an assessment in use cannot be deleted" do
    delete assessment_path(@assessment)
    assert_redirected_to assessment_path(@assessment)
    assert Assessment.exists?(@assessment.id)
  end

  test "bulk invite creates practical-assessment-only links for everyone" do
    assert_difference "Invitation.count", 2 do
      post exam_batches_path, params: {
        exam_batch: { name: "Accounts drive", interview_plan: "practical", assessment_id: @assessment.id,
                      vacancy_title: "Accounts Executive", max_warnings: 5, language: "en" },
        candidates: [ { candidate_name: "A One", candidate_phone: "9000000001" },
                      { candidate_name: "B Two", candidate_phone: "9000000002" } ]
      }
    end
    batch = ExamBatch.order(:id).last
    assert_nil batch.quiz_id
    assert_equal @assessment.id, batch.assessment_id
    batch.invitations.each do |invitation|
      assert_nil invitation.quiz_id
      assert_equal @assessment.id, invitation.assessment_id
      assert invitation.interview_rounds.sole.assessment?
    end

    get exam_batch_path(batch)
    assert_response :success
    get monitor_exam_batch_path(batch)
    assert_response :success
    get watch_batch_path(batch.watch_token)
    assert_response :success
  end

  test "switching a candidate from test-only to practical-only drops the paper and builds the task round" do
    quiz = @user.quizzes.create!(title: "Aptitude", duration_minutes: 10, pass_percentage: 50,
                                 questions_attributes: [ { body: "1+1?", options: [ "1", "2" ], correct_index: 1, marks: 1 } ])
    invitation = @user.invitations.create!(candidate_name: "Meena K", vacancy: "Clerk", quiz: quiz, interview_plan: "none")
    assert_empty invitation.interview_rounds

    patch invitation_path(invitation), params: { invitation: { candidate_name: "Meena K", vacancy: "Clerk",
                                                               interview_plan: "practical", assessment_id: @assessment.id } }
    assert_redirected_to invitation_path(invitation)
    invitation.reload
    assert_nil invitation.quiz_id
    assert invitation.practical_only?
    assert invitation.interview_rounds.reload.sole.assessment?
  end
end
