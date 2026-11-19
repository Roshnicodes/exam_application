require "test_helper"

# The MCQ online test end to end, so later changes can't quietly break it: OTP, start, answers,
# language switch, submit, hidden / shared result, HR pages and downloads, removing a candidate,
# and tests that run out of time.
class OnlineTestFlowTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @user.update!(name: "HR One")
    @quiz = @user.quizzes.create!(title: "Accounts basics", duration_minutes: 20, pass_percentage: 50, questions_attributes: [
      { body: "2 + 2 = ?", options: %w[3 4 5], correct_index: 1, marks: 1, position: 1 },
      { body: "GST on services is charged under?", options: %w[CGST IGST VAT], correct_index: 0, marks: 1, position: 2 },
      { body: "TDS stands for?", options: [ "Tax Deducted at Source", "Tax Due Soon" ], correct_index: 0, marks: 1, position: 3 }
    ])
    @questions = @quiz.questions.to_a
    @invitation = invite("Ravi Kumar", "9876511111")
  end

  test "a candidate takes the test and HR sees and shares the result" do
    token = @invitation.token
    get exam_path(token)
    assert_response :success

    post exam_request_otp_path(token), params: { phone: "9876511111" }
    assert_redirected_to exam_path(token, step: "otp")
    post exam_verify_otp_path(token), params: { otp: @invitation.reload.otp_code }
    assert_redirected_to exam_instructions_path(token)
    get exam_instructions_path(token)
    assert_response :success

    post exam_start_path(token)
    assert_redirected_to exam_take_path(token)
    assert @invitation.reload.in_progress?
    get exam_take_path(token)
    assert_response :success
    assert_match "2 + 2 = ?", response.body
    assert_match "lang-pick", response.body

    patch exam_answer_path(token), params: { question_id: @questions[0].id, option: 1 }, as: :json # right
    patch exam_answer_path(token), params: { question_id: @questions[1].id, option: 2 }, as: :json # wrong
    assert_equal 2, JSON.parse(response.body)["answered"]
    patch exam_language_path(token), params: { language: "hi" }, as: :json
    assert_response :no_content
    assert_equal "hi", @invitation.reload.language

    # the last answer comes with the submit; unknown question ids are ignored
    post exam_submit_path(token), params: { answers: { @questions[2].id.to_s => "0", "999999" => "1" } }
    assert_redirected_to exam_finished_path(token)
    @invitation.reload
    assert @invitation.submitted?
    assert_equal 2, @invitation.score
    assert_equal 3, @invitation.total_marks
    assert_not @invitation.answers.key?("999999")

    # the result stays hidden until HR shares it
    get exam_finished_path(token)
    assert_response :success
    assert_match "Your result will be shared by HR", response.body
    assert_no_match "score-ring", response.body

    sign_in_as @user
    [ root_path, invitations_path, invitations_path(group: "position"), invitations_path(status: "submitted"), invitation_path(@invitation),
      report_invitation_path(@invitation), pdf_invitation_path(@invitation), results_path, live_monitor_path, completed_monitor_path,
      pipeline_path, quizzes_path, quiz_path(@quiz) ].each do |path|
      get path
      assert_response :success, "#{path} should open"
    end
    get pdf_invitation_path(@invitation)
    assert_match "Ravi Kumar", response.body
    get export_invitation_path(@invitation)
    assert_response :success
    assert_match "spreadsheetml", response.media_type
    get export_invitations_path
    assert_response :success

    patch share_result_invitation_path(@invitation, visible: "1")
    assert @invitation.reload.result_visible?
    get exam_finished_path(token)
    assert_match "score-ring", response.body
    assert_match "67%", response.body
  end

  test "HR removes a candidate from a running test" do
    @invitation.update!(status: "in_progress", started_at: Time.current, verified_at: Time.current)
    sign_in_as @user
    patch remove_invitation_path(@invitation)
    @invitation.reload
    assert @invitation.terminated?
    assert_match "Removed by HR", @invitation.termination_reason
  end

  test "a test whose time ran out is submitted by itself" do
    @invitation.update!(status: "in_progress", started_at: 2.hours.ago, verified_at: 2.hours.ago,
                        answers: { @questions[0].id.to_s => 1 })
    Invitation.submit_overdue!
    @invitation.reload
    assert @invitation.finished?
    assert_equal "time_up", @invitation.termination_reason
    assert_equal 1, @invitation.score
  end

  private
    def invite(name, phone)
      @user.invitations.create!(candidate_name: name, candidate_phone: phone, vacancy: "Accountant", quiz: @quiz,
                                interview_plan: "none", max_warnings: 5)
    end
end
