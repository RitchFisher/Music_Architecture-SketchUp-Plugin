require 'sketchup.rb'
require 'json'

module MusicArchitecture
  # 默认参数
  @versions = []  # 存储所有组的数据
  @current_version_index = nil
  @current_note = "HN"  # 默认二分音符
  @dialog = nil
  @current_reference_point = Geom::Point3d.new(0, 0, 0)
  @placement_history = []  # 存储放置历史
  @highlight_material = nil
  @default_material = nil
  @previous_advance_dir = nil

  # 音符类型简写
  NOTE_TYPES = {
    "FN" => "Full Note",
    "HN" => "Half Note",
    "QN" => "Quarter Note",
    "EN" => "Eighth Note",
    "SN" => "Sixteenth Note"
  }

  # 添加菜单项
  unless file_loaded?(__FILE__)
    menu = UI.menu('Plugins')
    menu.add_item('Show Music Architecture Panel') { show_panel }
    file_loaded(__FILE__)
  end

  # 显示面板
  def self.show_panel
    if @dialog.nil? || !@dialog.visible?
      @dialog = UI::HtmlDialog.new(
        dialog_title: "Music Architecture",
        preferences_key: "MusicArchitecturePanel",
        width: 400,
        height: 900,
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
      @dialog.add_action_callback("adjustDimension") { |_, type, delta| adjust_dimension(type, delta) }
      @dialog.add_action_callback("changeDirection") { |_, action| change_direction(action) }
      @dialog.add_action_callback("undoLastPlacement") { |_| undo_last_placement }
      @dialog.add_action_callback("setDirection") { |_, dir| set_direction(dir) }
      @dialog.add_action_callback("setRotationAxis") { |_, axis| set_rotation_axis(axis) }
      @dialog.show
    end
    # 创建材质
    @highlight_material = Sketchup.active_model.materials.add("Highlight")
    @highlight_material.color = Sketchup::Color.new(150, 150, 255)  # 更亮的蓝色
    @default_material = Sketchup.active_model.materials.add("Default")
    @default_material.color = Sketchup::Color.new(255, 255, 255)
  end

  # 创建新组
  def self.create_new_group(params)
    group_id = @versions.size + 1
    group_data = {
      id: group_id,
      length: params['length'].to_f,
      width: params['width'].to_f,
      height: params['height'].to_f,
      advance_dir: params['advance_dir'],
      rotation_axis: params['rotation_axis'],
      base_spacing: params['spacing'].to_f,
      reference_point: @current_reference_point.to_a,
      standard_length: params['length'].to_f,
      standard_width: params['width'].to_f,
      standard_height: params['height'].to_f,
      previous_advance_dir: @previous_advance_dir
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
    group[:standard_length] = params['length'].to_f unless group[:standard_length]
    group[:standard_width] = params['width'].to_f unless group[:standard_width]
    group[:standard_height] = params['height'].to_f unless group[:standard_height]
    create_note_components(group)
    save_group_to_model(group, group[:id])
    highlight_current_group
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
    @previous_advance_dir = group[:previous_advance_dir]
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

  # 设置行进方向
  def self.set_direction(dir)
    return unless @current_version_index
    group = @versions[@current_version_index]
    if group[:advance_dir] != dir
      if (group[:advance_dir] == "X" && dir == "Y") || (group[:advance_dir] == "Y" && dir == "X")
        group[:length], group[:width] = group[:width], group[:length]
        group[:standard_length], group[:standard_width] = group[:standard_width], group[:standard_length]
      end
      @previous_advance_dir = group[:advance_dir]
      group[:advance_dir] = dir
      group[:previous_advance_dir] = @previous_advance_dir
      create_note_components(group)
      save_group_to_model(group, group[:id])
      update_panel_display
    end
  end

  # 设置旋转轴
  def self.set_rotation_axis(axis)
    return unless @current_version_index
    group = @versions[@current_version_index]
    group[:rotation_axis] = axis
    save_group_to_model(group, group[:id])
    update_panel_display
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

    # Z 轴行进时的预旋转
    tr = Geom::Transformation.new
    if group[:advance_dir] == "Z" && group[:previous_advance_dir]
      if group[:previous_advance_dir] == "X"
        tr = Geom::Transformation.rotation(@current_reference_point, [1, 0, 0], 90.degrees)
      elsif group[:previous_advance_dir] == "Y"
        tr = Geom::Transformation.rotation(@current_reference_point, [0, 1, 0], 90.degrees)
      end
      instance.transform!(tr)
    end

    # 按指定角度旋转
    axis = case group[:rotation_axis]
           when 'X' then [1, 0, 0]
           when 'Y' then [0, 1, 0]
           when 'Z' then [0, 0, 1]
           end
    tr_rotate = Geom::Transformation.rotation(@current_reference_point, axis, angle.degrees)
    instance.transform!(tr_rotate)

    @placement_history << { instance: instance, note_type: @current_note }
    @placement_history.shift if @placement_history.size > 100  # 限制历史大小
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

  # 同步间距
  def self.sync_spacing
    return unless @current_version_index
    group = @versions[@current_version_index]
    group[:base_spacing] = group[:length]
    save_group_to_model(group, group[:id])
    update_panel_display
  end

  # 反向间距
  def self.reverse_spacing
    return unless @current_version_index
    group = @versions[@current_version_index]
    group[:base_spacing] *= -1
    save_group_to_model(group, group[:id])
    update_panel_display
  end

  # 调整尺寸
  def self.adjust_dimension(type, delta)
    return unless @current_version_index
    group = @versions[@current_version_index]
    case type
    when "length"
      group[:length] += group[:standard_length] * delta
    when "width"
      group[:width] += group[:standard_width] * delta
    when "height"
      group[:height] += group[:standard_height] * delta
    end
    create_note_components(group)
    save_group_to_model(group, group[:id])
    update_panel_display
  end

  # 方向切换
  def self.change_direction(action)
    return unless @current_version_index
    group = @versions[@current_version_index]
    return if group[:advance_dir] == "Z"

    if action == "left"
      if group[:advance_dir] == "X" && group[:base_spacing] >= 0  # 北
        group[:advance_dir] = "Y"
        group[:length], group[:width] = group[:width], group[:length]
        group[:standard_length], group[:standard_width] = group[:standard_width], group[:standard_length]
      elsif group[:advance_dir] == "Y" && group[:base_spacing] >= 0  # 东
        group[:advance_dir] = "X"
        group[:base_spacing] *= -1
        group[:length], group[:width] = group[:width], group[:length]
        group[:standard_length], group[:standard_width] = group[:standard_width], group[:standard_length]
      elsif group[:advance_dir] == "X" && group[:base_spacing] < 0  # 南
        group[:advance_dir] = "Y"
        group[:base_spacing] *= -1
        group[:length], group[:width] = group[:width], group[:length]
        group[:standard_length], group[:standard_width] = group[:standard_width], group[:standard_length]
      elsif group[:advance_dir] == "Y" && group[:base_spacing] < 0  # 西
        group[:advance_dir] = "X"
      end
    elsif action == "right"
      if group[:advance_dir] == "X" && group[:base_spacing] >= 0  # 北
        group[:advance_dir] = "Y"
        group[:base_spacing] *= -1
        group[:length], group[:width] = group[:width], group[:length]
        group[:standard_length], group[:standard_width] = group[:standard_width], group[:standard_length]
      elsif group[:advance_dir] == "Y" && group[:base_spacing] >= 0  # 东
        group[:advance_dir] = "X"
        group[:length], group[:width] = group[:width], group[:length]
        group[:standard_length], group[:standard_width] = group[:standard_width], group[:standard_length]
      elsif group[:advance_dir] == "X" && group[:base_spacing] < 0  # 南
        group[:advance_dir] = "Y"
        group[:length], group[:width] = group[:width], group[:length]
        group[:standard_length], group[:standard_width] = group[:standard_width], group[:standard_length]
      elsif group[:advance_dir] == "Y" && group[:base_spacing] < 0  # 西
        group[:advance_dir] = "X"
        group[:base_spacing] *= -1
      end
    elsif action == "up"
      @previous_advance_dir = group[:advance_dir]
      group[:advance_dir] = "Z"
      group[:previous_advance_dir] = @previous_advance_dir
    elsif action == "down" && group[:previous_advance_dir]
      group[:advance_dir] = group[:previous_advance_dir]
      group[:previous_advance_dir] = nil
    end
    create_note_components(group)
    save_group_to_model(group, group[:id])
    update_panel_display
  end

  # 从选中组件获取参考点
  def self.get_reference_point_from_selection
    model = Sketchup.active_model
    selection = model.selection
    if selection.empty? || !selection.first.is_a?(Sketchup::ComponentInstance)
      UI.messagebox("请选中一个组件")
      return
    end
    instance = selection.first
    @current_reference_point = instance.transformation.origin
    group = @versions[@current_version_index]
    group[:reference_point] = @current_reference_point.to_a
    save_group_to_model(group, group[:id])
    update_panel_display
  end

  # 重置参考点
  def self.reset_reference_point
    return unless @current_version_index
    @current_reference_point = Geom::Point3d.new(0, 0, 0)
    group = @versions[@current_version_index]
    group[:reference_point] = @current_reference_point.to_a
   Kup.save_group_to_model(group, group[:id])
    save_group_to_model(group, group[:id])
    update_panel_display
  end

  # 高亮当前组
  def self.highlight_current_group
    model = Sketchup.active_model
    @versions.each_with_index do |group, index|
      material = (index == @current_version_index) ? @highlight_material : nil
      model.definitions.each do |defn|
        if defn.name.end_with?("_v#{group[:id]}")
          defn.instances.each do |inst|
            inst.definition.entities.each do |ent|
              ent.material = material if ent.is_a?(Sketchup::Face)
            end
          end
        end
      end
    end
  end

  # 回退
  def self.undo_last_placement
    return if @placement_history.empty?
    last = @placement_history.pop
    instance = last[:instance]
    note_type = last[:note_type]
    return unless instance && instance.valid?

    instance.erase!
    return unless @current_version_index

    group = @versions[@current_version_index]
    factor = {
      "FN" => 1.0,
      "HN" => 0.5,
      "QN" => 0.25,
      "EN" => 0.125,
      "SN" => 0.0625
    }
    spacing = group[:base_spacing] * factor[note_type]
    vector = case group[:advance_dir]
             when 'X' then [-spacing, 0, 0]
             when 'Y' then [0, -spacing, 0]
             when 'Z' then [0, 0, -spacing]
             end
    @current_reference_point += vector
    group[:reference_point] = @current_reference_point.to_a
    save_group_to_model(group, group[:id])
    update_panel_display
  end

  # 保存组数据到模型
  def self.save_group_to_model(group_data, group_id)
    model = Sketchup.active_model
    component_name = "GroupData_#{group_id}"
    definition = model.definitions[component_name]
    if definition.nil?
      definition = model.definitions.add(component_name)
      instance = model.entities.add_instance(definition, [0, 0, 0])
      instance.hidden = true
    else
      instance = model.entities.grep(Sketchup::ComponentInstance).find { |i| i.definition.name == component_name }
    end
    instance.set_attribute("MusicArch", "data", group_data.to_json)
  end

  # 从模型加载组数据
  def self.load_groups_from_model
    model = Sketchup.active_model
    @versions = []
    model.entities.each do |entity|
      if entity.is_a?(Sketchup::ComponentInstance) && entity.definition.name.start_with?("GroupData_")
        data = entity.get_attribute("MusicArch", "data")
        if data
          group_data = JSON.parse(data, symbolize_names: true)
          group_data[:reference_point] = Geom::Point3d.new(*group_data[:reference_point])
          @versions << group_data
        end
      end
    end
    @versions.sort_by! { |g| g[:id] }
    @current_version_index = @versions.any? ? 0 : nil
    highlight_current_group if @versions.any?
    update_panel_display
  end

  # 更新面板显示
  def self.update_panel_display
    if @current_version_index
      group = @versions[@current_version_index]
      @dialog.execute_script("document.getElementById('group_id').innerText = 'Group #{group[:id]}';")
      @dialog.execute_script("document.getElementById('length').value = '#{group[:length]}';")
      @dialog.execute_script("document.getElementById('width').value = '#{group[:width]}';")
      @dialog.execute_script("document.getElementById('height').value = '#{group[:height]}';")
      @dialog.execute_script("document.getElementById('advance_dir').value = '#{group[:advance_dir]}';")
      @dialog.execute_script("document.getElementById('rotation_axis').value = '#{group[:rotation_axis]}';")
      @dialog.execute_script("document.getElementById('spacing').value = '#{group[:base_spacing]}';")
      @dialog.execute_script("document.getElementById('ref_x').value = '#{group[:reference_point].x}';")
      @dialog.execute_script("document.getElementById('ref_y').value = '#{group[:reference_point].y}';")
      @dialog.execute_script("document.getElementById('ref_z').value = '#{group[:reference_point].z}';")
    else
      @dialog.execute_script("document.getElementById('group_id').innerText = '未选择';")
    end
  end

  # HTML内容
  def self.get_html_content
    <<~HTML
      <html>
      <body>
        <h2>Music Architecture 面板</h2>
        <p>当前组: <span id="group_id">未选择</span></p>
        <button onclick="loadGroups()">读取组数据</button>
        <h3>参数设置</h3>
        <form id="paramsForm">
          <label>长度 (X): <input type="text" id="length" value="3000"></label><br>
          <label>宽度 (Y): <input type="text" id="width" value="100"></label><br>
          <label>高度 (Z): <input type="text" id="height" value="3000"></label><br>
          <label>行进方向:
            <input type="text" id="advance_dir" value="X" readonly style="width: 30px;">
            <button type="button" onclick="setDirection('X')">X</button>
            <button type="button" onclick="setDirection('Y')">Y</button>
            <button type="button" onclick="setDirection('Z')">Z</button>
          </label><br>
          <label>旋转轴:
            <input type="text" id="rotation_axis" value="Z" readonly style="width: 30px;">
            <button type="button" onclick="setRotationAxis('X')">X</button>
            <button type="button" onclick="setRotationAxis('Y')">Y</button>
            <button type="button" onclick="setRotationAxis('Z')">Z</button>
          </label><br>
          <label>标准间距: <input type="text" id="spacing" value="3000"></label><br>
        </form>
        <h3>尺寸调整</h3>
        <button type="button" onclick="adjustDimension('length', 1)">+1倍长度</button>
        <button type="button" onclick="adjustDimension('length', -1)">-1倍长度</button>
        <button type="button" onclick="adjustDimension('width', 1)">+1倍宽度</button>
        <button type="button" onclick="adjustDimension('width', -1)">-1倍宽度</button>
        <button type="button" onclick="adjustDimension('height', 1)">+1倍高度</button>
        <button type="button" onclick="adjustDimension('height', -1)">-1倍高度</button>
        <button type="button" onclick="syncSpacing()">同步间距与长度</button>
        <button type="button" onclick="reverseSpacing()">反向间距</button>
        <h3>方向控制</h3>
        <button type="button" onclick="changeDirection('left')">左转</button>
        <button type="button" onclick="changeDirection('right')">右转</button>
        <button type="button" onclick="changeDirection('up')">向上</button>
        <button type="button" onclick="changeDirection('down')">向下</button>
        <h3>组管理</h3>
        <button type="button" onclick="createNewGroup()">创建新组</button>
        <button type="button" onclick="updateCurrentGroup()">保存到当前组</button>
        <button type="button" onclick="switchGroup('prev')">前一组</button>
        <button type="button" onclick="switchGroup('next')">后一组</button>
        <h3>参考点管理</h3>
        <p>X: <input type="text" id="ref_x" value="0"></p>
        <p>Y: <input type="text" id="ref_y" value="0"></p>
        <p>Z: <input type="text" id="ref_z" value="0"></p>
        <button onclick="updateReferencePoint()">更新参考点</button>
        <button onclick="resetReferencePoint()">重置参考点</button>
        <button onclick="getReferencePoint()">获取参考点</button>
        <h3>音符操作</h3>
        <h4>选择音符类型</h4>
        <button onclick="setNoteType('1')">FN (全音符)</button>
        <button onclick="setNoteType('2')">HN (二分音符)</button>
        <button onclick="setNoteType('3')">QN (四分音符)</button>
        <button onclick="setNoteType('4')">EN (八分音符)</button>
        <button onclick="setNoteType('5')">SN (十六分音符)</button>
        <h4>放置音符</h4>
        <button onclick="placeNote('z')">C (0°)</button>
        <button onclick="placeNote('s')">#C (15°)</button>
        <button onclick="placeNote('x')">D (30°)</button>
        <button onclick="placeNote('d')">#D (45°)</button>
        <button onclick="placeNote('c')">E (60°)</button>
        <button onclick="placeNote('v')">F (75°)</button>
        <button onclick="placeNote('g')">#F (90°)</button>
        <button onclick="placeNote('b')">G (105°)</button>
        <button onclick="placeNote('h')">#G (120°)</button>
        <button onclick="placeNote('n')">A (135°)</button>
        <button onclick="placeNote('j')">#A (150°)</button>
        <button onclick="placeNote('m')">B (165°)</button>
        <h4>其他操作</h4>
        <button onclick="advanceReferencePoint()">空拍 (0)</button>
        <button onclick="undoLastPlacement()">回退</button>
      </body>
      <script>
        function createNewGroup() {
          var params = getParams();
          sketchup.createNewGroup(params);
        }
        function updateCurrentGroup() {
          var params = getParams();
          sketchup.updateCurrentGroup(params);
        }
        function switchGroup(direction) {
          sketchup.switchGroup(direction);
        }
        function updateReferencePoint() {
          var x = document.getElementById('ref_x').value;
          var y = document.getElementById('ref_y').value;
          var z = document.getElementById('ref_z').value;
          sketchup.setReferencePoint(x, y, z);
        }
        function placeNote(key) { sketchup.placeNote(key); }
        function setNoteType(key) { sketchup.setNoteType(key); }
        function advanceReferencePoint() { sketchup.advanceReferencePoint(); }
        function syncSpacing() { sketchup.syncSpacing(); }
        function loadGroups() { sketchup.loadGroups(); }
        function resetReferencePoint() { sketchup.resetReferencePoint(); }
        function getReferencePoint() { sketchup.getReferencePoint(); }
        function reverseSpacing() { sketchup.reverseSpacing(); }
        function adjustDimension(type, delta) { sketchup.adjustDimension(type, delta); }
        function changeDirection(action) { sketchup.changeDirection(action); }
        function undoLastPlacement() { sketchup.undoLastPlacement(); }
        function setDirection(dir) { sketchup.setDirection(dir); }
        function setRotationAxis(axis) { sketchup.setRotationAxis(axis); }
        function getParams() {
          return {
            length: document.getElementById('length').value,
            width: document.getElementById('width').value,
            height: document.getElementById('height').value,
            advance_dir: document.getElementById('advance_dir').value,
            rotation_axis: document.getElementById('rotation_axis').value,
            spacing: document.getElementById('spacing').value
          };
        }
      </script>
      </html>
    HTML
  end
end