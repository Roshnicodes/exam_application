class VacanciesController < ApplicationController
  before_action :set_vacancy, only: %i[show edit update destroy]
  before_action :load_options, only: %i[new create edit update]

  def index
    @vacancies = Current.user.vacancies.ordered.includes(:department, :panelists)
    @vacancies = @vacancies.where(department_id: params[:department_id]) if params[:department_id].present?
    @departments = Current.user.departments.ordered
  end

  def show
    @invitations = @vacancy.invitations.includes(:quiz).recent
  end

  def new
    @vacancy = Current.user.vacancies.new(department_id: params[:department_id], issue_date: Date.current,
                                          end_date: 30.days.from_now.to_date,
                                          selection_parameters: [ { "name" => "Online test", "weight" => 40 },
                                                                  { "name" => "Technical interview", "weight" => 40 },
                                                                  { "name" => "HR interview", "weight" => 20 } ])
    redirect_to departments_path, alert: "Add a department first, then create vacancies." if @departments.empty?
  end

  def create
    @vacancy = Current.user.vacancies.new(vacancy_params.except(:panelist_ids))
    @vacancy.panelist_ids = vacancy_params[:panelist_ids]
    if @vacancy.save
      redirect_to @vacancy, notice: "Vacancy created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    @vacancy.assign_attributes(vacancy_params.except(:panelist_ids))
    @vacancy.panelist_ids = vacancy_params[:panelist_ids]
    if @vacancy.save
      redirect_to @vacancy, notice: "Vacancy updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @vacancy.destroy
    redirect_to vacancies_path, notice: "Vacancy deleted.", status: :see_other
  end

  private
    def set_vacancy
      @vacancy = Current.user.vacancies.find(params[:id])
    end

    def load_options
      @departments = Current.user.departments.active.ordered
      @employees = Current.user.employees.ordered
    end

    def vacancy_params
      params.expect(vacancy: [ :department_id, :title, :code, :issue_date, :end_date, :positions, :qualification,
                               :experience_required, :description, panelist_ids: [], selection_parameters: [ [ :name, :weight ] ] ])
    end
end
