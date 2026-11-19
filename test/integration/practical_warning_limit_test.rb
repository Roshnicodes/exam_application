require "test_helper"

# A practical test's warning setting decides when the candidate's work is submitted — also for
# rounds created before HR changed it (e.g. to "Never").
class PracticalWarningLimitTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @assessment = @user.assessments.create!(title: "Tally entry", description: "Sales entries", kind: "tally",
                                            duration_minutes: 30, max_marks: 20, pass_percentage: 50, max_warnings: 5)
  end

  test "with “Never” the candidate is not stopped, even if the round was given earlier" do
    invitation, round = start_practical
    round.update_columns(max_warnings: 5) # rounds made before this fix kept a copy of the limit
    assert_equal 5, round.warning_limit

    @assessment.update!(max_warnings: 0) # HR switches to "Never" after inviting
    assert_equal 0, round.reload.warning_limit

    8.times { post exam_events_path(invitation.token), params: { kind: "tab_switch", round_id: round.id } }
    body = JSON.parse(response.body)
    assert_not body["terminated"]
    assert_equal 8, body["warnings"]
    assert round.reload.working?
  end

  test "a limit still submits the work when it is reached" do
    @assessment.update!(max_warnings: 3)
    invitation, round = start_practical
    3.times { post exam_events_path(invitation.token), params: { kind: "tab_switch", round_id: round.id } }
    assert JSON.parse(response.body)["terminated"]
    assert round.reload.submitted?
    assert_match "Warning limit reached (3/3)", round.termination_reason
  end

  test "a limit HR set for one candidate is kept when the practical test changes" do
    invitation, round = start_practical
    round.update!(max_warnings: 8) # chosen on purpose for this candidate
    @assessment.update!(max_warnings: 0)
    assert_equal 8, round.reload.warning_limit
    assert invitation
  end

  private
    def start_practical
      invitation = @user.invitations.create!(candidate_name: "Asha Rao", candidate_phone: "9876500000", vacancy: "Accountant",
                                             assessment: @assessment, interview_plan: "practical", max_warnings: 5)
      round = invitation.interview_rounds.sole
      post exam_request_otp_path(invitation.token), params: { phone: "9876500000" }
      post exam_verify_otp_path(invitation.token), params: { otp: invitation.reload.otp_code }
      round.open!
      post exam_assessment_start_path(invitation.token)
      [ invitation, round.reload ]
    end
end
