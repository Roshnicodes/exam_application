class DepartmentsController < ApplicationController
  before_action :set_department, only: %i[edit update destroy]

  def index
    @departments = Current.user.departments.ordered.includes(:vacancies)
    @department = Current.user.departments.new
  end

  def new
    @department = Current.user.departments.new
  end

  def create
    @department = Current.user.departments.new(department_params)
    if @department.save
      redirect_to departments_path, notice: "Department '#{@department.name}' added."
    else
      @departments = Current.user.departments.ordered.includes(:vacancies)
      render :index, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @department.update(department_params)
      redirect_to departments_path, notice: "Department updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if @department.destroy
      redirect_to departments_path, notice: "Department deleted.", status: :see_other
    else
      redirect_to departments_path, alert: "Remove this department's vacancies first.", status: :see_other
    end
  end

  private
    def set_department
      @department = Current.user.departments.find(params[:id])
    end

    def department_params
      params.expect(department: %i[name head_name description active])
    end
end
