class VacancyPanelist < ApplicationRecord
  belongs_to :vacancy
  belongs_to :employee
end
