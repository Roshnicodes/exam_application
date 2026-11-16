require "test_helper"

# Excel practical solved in the built-in spreadsheet: the candidate fills HR's workbook on the
# assessment page (no download / upload); on submit it becomes an .xlsx with their formulas.
class SheetAssessmentTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @user.update!(name: "HR One")
    @assessment = @user.assessments.create!(title: "Sales sheet", description: "Sales workbook with VLOOKUP", kind: "excel", duration_minutes: 30, max_marks: 20,
                                            pass_percentage: 50, instructions: "Fill Rate with VLOOKUP and Amount = Qty x Rate")
    @assessment.files.attach(io: StringIO.new(task_workbook), filename: "HR_Task_Sales.xlsx",
                             content_type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")
  end

  test "candidate solves the Excel task in the built-in spreadsheet and HR gets an .xlsx" do
    invitation = @user.invitations.create!(candidate_name: "Asha Rao", candidate_phone: "9876500000", vacancy: "Accountant",
                                           assessment: @assessment, interview_plan: "practical", max_warnings: 5)
    round = invitation.interview_rounds.sole
    token = invitation.token
    assert round.online_sheet?

    post exam_request_otp_path(token), params: { phone: "9876500000" }
    post exam_verify_otp_path(token), params: { otp: invitation.reload.otp_code }
    round.open!
    post exam_assessment_start_path(token)

    get exam_assessment_path(token)
    assert_response :success
    assert_match "Your answer sheet", response.body
    assert_match "No upload needed", response.body # the sheet saves and submits by itself
    assert_no_match "Upload your finished work", response.body
    assert_no_match "up-zone", response.body

    # the task workbook, with HR's formula kept as a formula
    get exam_assessment_sheet_path(token), as: :json
    assert_response :success
    sheets = JSON.parse(response.body)["sheets"]
    assert_equal [ "Sales", "Price List" ], sheets.map { |s| s["name"] }
    assert_equal [ "Invoice", "Product", "Qty", "Rate", "Amount" ], sheets[0]["cells"][0]
    assert_equal "=SUM(E2:E3)", sheets[0]["cells"][3][4]

    # the candidate fills Rate / Amount with formulas; autosave
    cells = sheets[0]["cells"]
    cells[1][3] = "=VLOOKUP(B2,'Price List'!A:B,2,FALSE)"
    cells[1][4] = "=C2*D2"
    values = cells.map { |row| row.map { "" } }
    values[1][3] = "450"
    values[1][4] = "5400"
    styles = { "0:0" => { "b" => true, "bg" => "#FFFF00" }, "1:4" => { "fmt" => "currency" }, "1:2" => { "fmt" => "currency" }, "2:2" => { "b" => "javascript:alert(1)", "bg" => "red;x" } }
    patch exam_assessment_sheet_save_path(token), params: { sheets: [ { name: "Sales", cells: cells, values: values, styles: styles, widths: { "1" => 140, "x" => 5 } }, sheets[1] ] }, as: :json
    assert_response :success
    assert round.reload.sheet_saved_at
    saved = round.sheet_data["sheets"][0]
    assert_equal({ "b" => true, "bg" => "#ffff00" }, saved["styles"]["0:0"])
    assert_equal({ "fmt" => "currency" }, saved["styles"]["1:4"])
    assert_nil saved["styles"]["2:2"] # junk is dropped
    assert_equal({ "1" => 140 }, saved["widths"])

    # reopening the page brings back the candidate's work
    get exam_assessment_sheet_path(token), as: :json
    assert_equal "=C2*D2", JSON.parse(response.body)["sheets"][0]["cells"][1][4]

    # no upload needed: the answer sheet is the work
    post exam_assessment_submit_path(token)
    assert_redirected_to exam_assessment_path(token)
    assert round.reload.submitted?

    answer = round.submissions.attachments.sole
    assert answer.filename.to_s.start_with?("Answer - HR_Task_Sales")
    book = answer.blob.open { |tmp| Roo::Excelx.new(tmp.path) }
    assert_equal "C2*D2", book.sheet("Sales").formula(2, 5).to_s.delete_prefix("=")
    assert_equal 5400, book.sheet("Sales").cell(2, 5).to_i
    assert_equal "Price List", book.sheets.last
    assert book.sheet("Sales").font(1, 1).bold?
    styles_xml = answer.blob.open { |tmp| Zip::File.open(tmp.path) { |zip| zip.read("xl/styles.xml").force_encoding("UTF-8") } }
    assert_includes styles_xml, "₹" # the ₹ number format goes into the workbook

    # HR sees the answer sheet on the page, changed cells marked
    sign_in_as @user
    get room_invitation_interview_round_path(invitation, round)
    assert_response :success
    assert_match "Answer sheet", response.body
    assert_match "sa-changed", response.body
  end

  test "the built-in sheet only saves while the candidate is working" do
    invitation = @user.invitations.create!(candidate_name: "Ravi", candidate_phone: "9876500001", vacancy: "Accountant",
                                           assessment: @assessment, interview_plan: "practical", max_warnings: 5)
    token = invitation.token
    post exam_request_otp_path(token), params: { phone: "9876500001" }
    post exam_verify_otp_path(token), params: { otp: invitation.reload.otp_code }
    patch exam_assessment_sheet_save_path(token), params: { sheets: [ { name: "Sales", cells: [ [ "x" ] ] } ] }, as: :json
    assert_response :unprocessable_entity
    get exam_assessment_sheet_path(token), as: :json
    assert_response :not_found
  end

  private
    def task_workbook
      package = Axlsx::Package.new
      package.workbook.add_worksheet(name: "Sales") do |ws|
        ws.add_row [ "Invoice", "Product", "Qty", "Rate", "Amount" ]
        ws.add_row [ "INV-1", "Wheat Seeds", 12, nil, nil ]
        ws.add_row [ "INV-2", "Sprayer Pump", 3, nil, nil ]
        ws.add_row [ nil, nil, nil, "Total", "=SUM(E2:E3)" ], escape_formulas: false, formula_values: [ nil, nil, nil, nil, "0" ] # Excel keeps the value too
      end
      package.workbook.add_worksheet(name: "Price List") do |ws|
        ws.add_row [ "Product", "Rate" ]
        ws.add_row [ "Wheat Seeds", 450 ]
        ws.add_row [ "Sprayer Pump", 2200 ]
      end
      package.to_stream.read
    end
end
