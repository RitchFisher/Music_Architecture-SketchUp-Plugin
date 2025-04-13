require 'sketchup.rb'
require 'json'

module MusicArchitecture
  # 默认参数
  @versions = []  # 存储所有组的数据
  @current_version_index = nil
  @current_note = "HN"  # 默认二分音符
  @dialog = nil
  @current_reference_point = Geom::Point3d.new(0, 0, 0)
  @last_placed_instance = nil
  @last_note_type = nil
  @previous_advance_dir = nil

  # 音符类型简写
  NOTE_TYPES = {
    "FN" => "Full Note",
    "HN" => "Half Note",
    "QN" => "Quarter Note",
    "EN" => "Eighth Note",
    "SN" => "Sixteenth Note"
  }

  # 材质
  @default_material = nil
  @highlight_material = nil

  # 添加菜单项
  unless file_loaded?(__FILE__)
    menu = UI.menu('Plugins')
    menu.add_item('Show Music Architecture Panel') { show_panel }
    file_loaded(__FILE__)
  end

  # 创建蓝色材质
  def self.create_materials
    model = Sketchup.active_model
    @default_material = model.materials["DefaultMaterial"] || model.materials.add("DefaultMaterial")
    @highlight_material = model.materials.add("HighlightMaterial")
    @highlight_material.color = Sketchup::Color.new(100, 100, 255)  # 低饱和度蓝色
  end

  # 显示面板
  def self.show_panel
    create_materials
    if @dialog.nil? || !@dialog.visible?
      @dialog = UI::HtmlDialog.new(
        dialog_title: "Music Architecture",
        preferences_key: "MusicArchitecturePanel",
        width: 450,
        height: 800,
        left: 100,
        top: 100,
        resizable: true
      )
      @dialog.set_html(get_html_content)
      @dialog.add_action_callback("createNewGroup") { |_, params| create_new_group(params) }
      @dialog.add_action_callback("updateCurrentGroup") { |_, params| update_current_group(params) }
      @dialog.add_action_callback("switchGroup") { |_, direction| switch_group(direction) }
      @dialog.add_action_callback("setReferencePoint") { |_, x, y, z| set_reference_point(x, y, z) }
      @dialog.add_action_callback("placeNote") { |_, key| place_note(key) }
      @dialog.add_action_callback("setNoteType") { |_, key| set_note_type(key) }
      @dialog.add_action_callback("advanceReferencePoint") { |_| advance_reference_point }
      @dialog.add_action_callback("syncSpacing") { |_| sync_spacing }
      @dialog.add_action_callback("loadGroups") { |_| load_groups_from_model }
      @dialog.add_action_callback("resetReferencePoint") { |_| reset_reference_point }
      @dialog.add_action_callback("getReferencePoint") { |_| get_reference_point_from_selection }
      @dialog.add_action_callback("reverseSpacing") { |_| reverse_spacing }
      @dialog.add_action_callback("adjustHeight") { |_, delta| adjust_height(delta) }
      @dialog.add_action_callback("changeDirection") { |_, action| change_direction(action) }
      @dialog.add_action_callback("undoLastPlacement") { |_| undo_last_placement }
      @dialog.show
    end
  end

  # 创建新组
  def self.create_new_group(params)
    group_id = @versions.size + 1
    group_data = {
      id: group_id,
      length: 3000.0,  # 默认3000
      width: params['width'].to_f || 100.0,
      height: params['height'].to_f || 3000.0,
      advance_dir: params['advance_dir'] || 'Y',
      rotation_axis: params['rotation_axis'] || 'Z',
      base_spacing: 3000.0,  # 默认3000
      reference_point: @current_reference_point.to_a,
      standard_height: params['height'].to_f || 3000.0
    }
    @versions << group_data
    @current_version_index = @versions.size - 1
    create_note_components(group_data)
    save_group_to_model(group_data, group_id)
    highlight_current_group
    update_panel_display
  end

  # 更新当前组
  def self.update_current_group(params)
    return unless @current_version_index
    group = @versions[@current_version_index]
    group[:length] = params['length'].to_f
    group[:width] = params['width'].to_f
    group[:height] = params['height'].to_f
    group[:advance_dir] = params['advance_dir']
    group[:rotation_axis] = params['rotation_axis']
    group[:base_spacing] = params['spacing'].to_f
    create_note_components(group)
    save_group_to_model(group, group[:id])
    update_panel_display
  end

  # 切换组
  def self.switch_group(direction)
    return unless @current_version_index
    if direction == "prev" && @current_version_index > 0
      @current_version_index -= 1
    elsif direction == "next" && @current_version_index < @versions.size - 1
      @current_version_index += 1
    end
    group = @versions[@current_version_index]
    @current_reference_point = Geom::Point3d.new(*group[:reference_point])
    highlight_current_group
    update_panel_display
  end

  # 设置参考点
  def self.set_reference_point(x, y, z)
    return unless @current_version_index
    @current_reference_point = Geom::Point3d.new(x.to_f, y.to_f, z.to_f)
    group = @versions[@current_version_index]
    group[:reference_point] = @current_reference_point.to_a
    save_group_to_model(group, group[:id])
    update_panel_display
  end

  # 重置参考点为 (0, 0, 0)
  def self.reset_reference_point
    return unless @current_version_index
    @current_reference_point = Geom::Point3d.new(0, 0, 0)
    group = @versions[@current_version_index]
    group[:reference_point] = @current_reference_point.to_a
    save_group_to_model(group, group[:id])
    update_panel_display
  end

  # 从选中的组件获取参考点
  def self.get_reference_point_from_selection
    selection = Sketchup.active_model.selection
    if selection.size == 1 && selection.first.is_a?(Sketchup::ComponentInstance)
      @current_reference_point = selection.first.transformation.origin
      group = @versions[@current_version_index]
      group[:reference_point] = @current_reference_point.to_a
      save_group_to_model(group, group[:id])
      update_panel_display
    else
      UI.messagebox("请选中一个组件。")
    end
  end

  # 创建音符组件
  def self.create_note_components(group_data)
    model = Sketchup.active_model
    definitions = model.definitions
    note_types = {
      "FN" => 1.0,
      "HN" => 0.5,
      "QN" => 0.25,
      "EN" => 0.125,
      "SN" => 0.0625
    }
    note_types.each do |type, factor|
      component_name = "#{type}_v#{group_data[:id]}"
      definition = definitions[component_name]
      if definition
        definition.entities.clear!
      else
        definition = definitions.add(component_name)
      end
      length = group_data[:length] * factor
      create_rectangle(definition, length, group_data[:width], group_data[:height])
    end
  end

  # 创建长方体
  def self.create_rectangle(definition, length, width, height)
    entities = definition.entities
    points = [
      [-length/2, -width/2, -height/2],
      [length/2, -width/2, -height/2],
      [length/2, width/2, -height/2],
      [-length/2, width/2, -height/2]
    ]
    face = entities.add_face(points)
    face.pushpull(height)
  end

  # 放置音符
  def self.place_note(key)
    return unless @current_version_index
    group = @versions[@current_version_index]
    note_map = {
      'z' => 0, 's' => 15, 'x' => 30, 'd' => 45, 'c' => 60, 'v' => 75,
      'g' => 90, 'b' => 105, 'h' => 120, 'n' => 135, 'j' => 150, 'm' => 165
    }
    angle = note_map[key]
    model = Sketchup.active_model
    entities = model.active_entities
    component_name = "#{@current_note}_v#{group[:id]}"
    definition = model.definitions[component_name]
    instance = entities.add_instance(definition, @current_reference_point)

    # 旋转
    axis = case group[:rotation_axis]
           when 'X' then [1, 0, 0]
           when 'Y' then [0, 1, 0]
           when 'Z' then [0, 0, 1]
           end
    tr_rotate = Geom::Transformation.rotation(@current_reference_point, axis, angle.degrees)
    instance.transform!(tr_rotate)

    @last_placed_instance = instance
    @last_note_type = @current_note

    advance_reference_point
  end

  # 移动参考点
  def self.advance_reference_point
    return unless @current_version_index
    group = @versions[@current_version_index]
    factor = {
      "FN" => 1.0,
      "HN" => 0.5,
      "QN" => 0.25,
      "EN" => 0.125,
      "SN" => 0.0625
    }
    spacing = group[:base_spacing] * factor[@current_note]
    vector = case group[:advance_dir]
             when 'X' then [spacing, 0, 0]
             when 'Y' then [0, spacing, 0]
             when 'Z' then [0, 0, spacing]
             end
    @current_reference_point += vector
    group[:reference_point] = @current_reference_point.to_a
    save_group_to_model(group, group[:id])
    update_panel_display
  end

  # 设置音符类型
  def self.set_note_type(key)
    note_types = { '1' => "FN", '2' => "HN", '3' => "QN", '4' => "EN", '5' => "SN" }
    @current_note = note_types[key]
  end

  # 同步间距与长度
  def self.sync_spacing
    return unless @current_version_index
    group = @versions[@current_version_index]
    group[:base_spacing] = group[:length]
    update_panel_display
  end

  # 反向间距
  def self.reverse_spacing
    return unless @current_version_index
    group = @versions[@current_version_index]
    group[:base_spacing] *= -1
    update_panel_display
  end

  # 调整高度
  def self.adjust_height(delta)
    return unless @current_version_index
    group = @versions[@current_version_index]
    group[:height] += group[:standard_height] * delta
    update_panel_display
  end

  # 改变方向
  def self.change_direction(action)
    return unless @current_version_index
    group = @versions[@current_version_index]
    current_dir = group[:advance_dir]
    current_spacing = group[:base_spacing]

    if action == "left"
      if current_dir == 'X' && current_spacing > 0
        group[:advance_dir] = 'Y'
        group[:base_spacing] = -current_spacing
      elsif current_dir == 'Y' && current_spacing < 0
        group[:advance_dir] = 'X'
        group[:base_spacing] = -current_spacing
      # 其他逻辑...
      end
    # 实现其他方向...
    end

    if (current_dir == 'X' && group[:advance_dir] == 'Y') || (current_dir == 'Y' && group[:advance_dir] == 'X')
      group[:length], group[:width] = group[:width], group[:length]
    end

    if group[:advance_dir] == 'Z'
      if @previous_advance_dir == 'X'
        # 绕 X 轴旋转 90 度
      elsif @previous_advance_dir == 'Y'
        # 绕 Y 轴旋转 90 度
      end
    end

    @previous_advance_dir = group[:advance_dir]
    update_panel_display
  end

  # 回退上一个放置
  def self.undo_last_placement
    if @last_placed_instance
      @last_placed_instance.erase!
      group = @versions[@current_version_index]
      factor = {
        "FN" => 1.0,
        "HN" => 0.5,
        "QN" => 0.25,
        "EN" => 0.125,
        "SN" => 0.0625
      }
      spacing = group[:base_spacing] * factor[@last_note_type]
      vector = case group[:advance_dir]
               when 'X' then [-spacing, 0, 0]
               when 'Y' then [0, -spacing, 0]
               when 'Z' then [0, 0, -spacing]
               end
      @current_reference_point += vector
      group[:reference_point] = @current_reference_point.to_a
      save_group_to_model(group, group[:id])
      update_panel_display
      @last_placed_instance = nil
    end
  end

  # HTML内容（简化版）
  def self.get_html_content
    <<~HTML
      <html>
      <body>
        <!-- 参数输入和按钮 -->
        <button onclick="createNewGroup()">创建新组</button>
        <button onclick="updateCurrentGroup()">保存到当前组</button>
        <button onclick="syncSpacing()">同步间距与长度</button>
        <button onclick="reverseSpacing()">反向间距</button>
        <button onclick="adjustHeight(1)">+1倍高度</button>
        <button onclick="adjustHeight(-1)">-1倍高度</button>
        <button onclick="changeDirection('left')">左转</button>
        <button onclick="changeDirection('right')">右转</button>
        <button onclick="undoLastPlacement()">回退</button>
        <!-- 其他按钮和功能 -->
      </body>
      <script>
        // JavaScript 回调函数
      </script>
      </html>
    HTML
  end
end