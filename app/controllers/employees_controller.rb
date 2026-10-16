class EmployeesController < ApplicationController
  before_action :set_employee, only: %i[edit update destroy]

  PER_PAGE = 48

  def index
    @employee = Current.user.employees.new
    load_directory
  end

  def create
    @employee = Current.user.employees.new(employee_params)
    if @employee.save
      redirect_to employees_path, notice: "#{@employee.name} added."
    else
      load_directory
      render :index, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @employee.update(employee_params)
      redirect_to employees_path, notice: "Employee updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @employee.destroy
    redirect_to employees_path, notice: "Employee removed.", status: :see_other
  end

  def import
    result = Employee.import(Current.user, params[:file])
    message = "Imported: #{result[:created]} added, #{result[:updated]} updated."
    if result[:errors].any?
      redirect_to employees_path, alert: "#{message} #{result[:errors].size} row(s) skipped — #{result[:errors].first(3).join('; ')}"
    else
      redirect_to employees_path, notice: message
    end
  rescue Spreadsheet::Error => e
    redirect_to employees_path, alert: e.message
  end

  def template
    data = Spreadsheet.build("Employees", Employee::HEADERS,
                             [ [ "EMP001", "Anita Desai", "anita@company.com", "9876500001", "Engineering", "Engineering Manager" ],
                               [ "EMP002", "Vikram Singh", "vikram@company.com", "9876500002", "Human Resources", "HR Manager" ] ],
                             widths: [ 16, 26, 30, 16, 22, 26 ],
                             notes: [ "Keep the header row. Name is required.", "Employee Code (or Email) is used to update existing employees on re-upload." ])
    send_xlsx data, "employee_template.xlsx"
  end

  def export
    rows = Current.user.employees.ordered.map { |e| [ e.employee_code, e.name, e.email, e.phone, e.department_name, e.designation ].map(&:to_s) }
    send_xlsx Spreadsheet.build("Employees", Employee::HEADERS, rows, widths: [ 16, 26, 30, 16, 22, 26 ]), "employees.xlsx"
  end

  private
    def load_directory
      all = Current.user.employees
      @stats = {
        total: all.count,
        departments: all.where.not(department_name: nil).distinct.count(:department_name),
        with_email: all.where.not(email: nil).count,
        panelists: VacancyPanelist.joins(:employee).where(employees: { user_id: Current.user.id }).distinct.count(:employee_id)
      }
      @department_counts = all.group(:department_name).order(Arel.sql("COUNT(*) DESC")).count
      scope = all.search(params[:q])
      scope = params[:department] == "none" ? scope.where(department_name: nil) : scope.where(department_name: params[:department]) if params[:department].present?
      @filtered_count = scope.count
      @pages = [ (@filtered_count / PER_PAGE.to_f).ceil, 1 ].max
      @page = params[:page].to_i.clamp(1, @pages)
      @employees = scope.ordered.includes(:vacancies).offset((@page - 1) * PER_PAGE).limit(PER_PAGE)
    end

    def set_employee
      @employee = Current.user.employees.find(params[:id])
    end

    def employee_params
      params.expect(employee: %i[employee_code name email phone department_name designation])
    end
end
