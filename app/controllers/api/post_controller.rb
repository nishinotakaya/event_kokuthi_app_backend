module Api
  class PostController < ApplicationController
    # Enqueue a background PostJob and return job_id for ActionCable subscription
    def create
      job_id = SecureRandom.hex(8)

      payload = {
        'content'      => params[:content].to_s,
        'sites'        => Array(params[:sites]),
        'eventFields'  => params[:eventFields]&.to_unsafe_h || {},
        'generateImage' => params[:generateImage],
        'imageStyle'   => params[:imageStyle],
        'openaiApiKey' => params[:openaiApiKey].presence || ENV['OPENAI_API_KEY'],
      }

      if payload['sites'].empty?
        return render json: { error: '投稿先が選択されていません' }, status: :unprocessable_entity
      end

      PostJob.perform_later(job_id, payload)

      render json: { job_id: job_id }
    end
  end
end
