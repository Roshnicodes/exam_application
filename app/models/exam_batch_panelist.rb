class ExamBatchPanelist < ApplicationRecord
  belongs_to :exam_batch
  belongs_to :employee
end
