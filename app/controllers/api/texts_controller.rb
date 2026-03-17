module Api
  class TextsController < ApplicationController
    def index
      items = Item.where(item_type: params[:type]).order(:created_at)
      render json: items.map { |i| format_item(i) }
    end

    def create
      item = Item.new(
        item_type: params[:type],
        name:      item_params[:name],
        content:   item_params[:content],
        folder:    item_params[:folder] || ''
      )
      if item.save
        render json: format_item(item)
      else
        render json: { error: item.errors.full_messages.join(', ') }, status: :unprocessable_entity
      end
    end

    def update
      item = Item.find_by(id: params[:id], item_type: params[:type])
      return render json: { error: 'Not found' }, status: :not_found unless item

      item.assign_attributes(
        name:    item_params[:name]    || item.name,
        content: item_params[:content] || item.content,
      )
      item.folder = item_params[:folder] if item_params.key?(:folder)
      item.updated_at = Time.current
      item.save!
      render json: format_item(item)
    end

    def destroy
      item = Item.find_by(id: params[:id], item_type: params[:type])
      return render json: { error: 'Not found' }, status: :not_found unless item

      item.destroy
      render json: { ok: true }
    end

    private

    def item_params
      params.permit(:name, :content, :folder)
    end

    def format_item(item)
      {
        id:        item.id,
        name:      item.name,
        type:      item.item_type,
        content:   item.content,
        folder:    item.folder || '',
        createdAt: item.created_at&.strftime('%Y-%m-%d'),
        updatedAt: item.updated_at&.strftime('%Y-%m-%d'),
      }
    end
  end
end
