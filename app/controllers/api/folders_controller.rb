module Api
  class FoldersController < ApplicationController
    def index
      render json: build_tree(params[:type])
    end

    def create
      type   = params[:type]
      name   = params[:name]
      parent = params[:parent].presence

      return render json: { error: 'name required' }, status: :bad_request unless name
      return render json: { error: 'フォルダ名にスラッシュは使えません' }, status: :bad_request if name.include?('/')

      if parent
        # 子フォルダ追加
        return render json: { error: 'parent not found' }, status: :not_found unless Folder.exists?(folder_type: type, name: parent, parent: nil)
        return render json: { error: 'already exists' }, status: :conflict if Folder.exists?(folder_type: type, name: name, parent: parent)
        Folder.create!(folder_type: type, name: name, parent: parent)
      else
        # 親フォルダ追加
        return render json: { error: 'already exists' }, status: :conflict if Folder.exists?(folder_type: type, name: name, parent: nil)
        Folder.create!(folder_type: type, name: name, parent: nil)
      end

      render json: { ok: true, folders: build_tree(type) }
    end

    def update
      type        = params[:type]
      folder_path = params[:path]
      new_name    = params[:newName]

      return render json: { error: 'path and newName required' }, status: :bad_request unless folder_path && new_name
      return render json: { error: 'フォルダ名にスラッシュは使えません' }, status: :bad_request if new_name.include?('/')

      # DB参照でルート/子を判定（パス中のスラッシュに依存しない）
      root = Folder.find_by(folder_type: type, name: folder_path, parent: nil)
      if root
        return render json: { error: 'already exists' }, status: :conflict if Folder.exists?(folder_type: type, name: new_name, parent: nil)
        old_name = root.name
        root.update!(name: new_name)
        Folder.where(folder_type: type, parent: old_name).update_all(parent: new_name)
        Item.where(item_type: type, folder: old_name).update_all(folder: new_name)
        Item.where(item_type: type).where('folder LIKE ?', "#{old_name}/%").each do |item|
          item.update_column(:folder, item.folder.sub("#{old_name}/", "#{new_name}/"))
        end
      elsif folder_path.include?('/')
        parent_name, old_child = folder_path.split('/', 2)
        child = Folder.find_by(folder_type: type, name: old_child, parent: parent_name)
        return render json: { error: 'not found' }, status: :not_found unless child
        return render json: { error: 'already exists' }, status: :conflict if Folder.exists?(folder_type: type, name: new_name, parent: parent_name)
        child.update!(name: new_name)
        Item.where(item_type: type, folder: folder_path).update_all(folder: "#{parent_name}/#{new_name}")
      else
        return render json: { error: 'not found' }, status: :not_found
      end

      render json: { ok: true, folders: build_tree(type) }
    end

    def destroy
      type        = params[:type]
      folder_path = params[:path].to_s

      # DB参照でルート/子を判定（パス中のスラッシュに依存しない）
      root = Folder.find_by(folder_type: type, name: folder_path, parent: nil)
      if root
        children   = Folder.where(folder_type: type, parent: folder_path).pluck(:name)
        child_paths = children.map { |c| "#{folder_path}/#{c}" }
        Folder.where(folder_type: type, name: folder_path, parent: nil).destroy_all
        Folder.where(folder_type: type, parent: folder_path).destroy_all
        Item.where(item_type: type, folder: [folder_path] + child_paths).update_all(folder: '')
      elsif folder_path.include?('/')
        parent_name, child_name = folder_path.split('/', 2)
        Folder.where(folder_type: type, name: child_name, parent: parent_name).destroy_all
        Item.where(item_type: type, folder: folder_path).update_all(folder: parent_name)
      end

      render json: { ok: true }
    end

    private

    def build_tree(type)
      parents  = Folder.where(folder_type: type, parent: nil).order(:created_at)
      all_children = Folder.where(folder_type: type).where.not(parent: nil).order(:created_at)

      parents.map do |p|
        children = all_children.select { |c| c.parent == p.name }.map(&:name)
        { name: p.name, children: children }
      end
    end
  end
end
