require 'sketchup.rb'
require 'json'

module MusicArchitecture
  @versions = []
  @current_version_index = nil
  @current_note = "HN"
  @dialog = nil
  @current_reference_point = Geom::Point3d.new(0, 0, 0)
  @placement_history = []
  @highlight_material = nil
  @default_material = nil
  @saved_direction = nil
  @last_action = nil
  @next_group_id = 1

  # 方向映射常量
  DIR_MAP = {
    "X+" => ["Y+", "Y-"],
    "Y+" => ["X-", "X+"],
    "X-" => ["Y-", "Y+"],
    "Y-" => ["X+", "X-"]
  }.freeze

  REVERSE_DIR_MAP = {
    "X+" => "X-",
    "X-" => "X+",
    "Y+" => "Y-",
    "Y-" => "Y+",
    "Z" => "Z-",
    "Z-" => "Z"
  }.freeze

  # 音符类型和因子
  NOTE_TYPES = {
    "FN" => "Full Note", "HN" => "Half Note", "QN" => "Quarter Note",
    "EN" => "Eighth Note", "SN" => "Sixteenth Note"
  }.freeze

  NOTE_FACTORS = {
    "FN" => 1.0, "HN" => 0.5, "QN" => 0.25, "EN" => 0.125, "SN" => 0.0625
  }.freeze

  def self.mm_to_inch(mm)
    mm / 25.4
  end

  def self.inch_to_mm(inch)
    inch * 25.4
  end

  unless file_loaded?(__FILE__)
    menu = UI.menu('Plugins')
    menu.add_item('Show Music Architecture Panel') { show_panel }
    file_loaded(__FILE__)
  end

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
      @dialog.add_action_callback("syncWidth") { |_| sync_width }
      @dialog.add_action_callback("loadGroups") { |_| load_groups_from_model }
      @dialog.add_action_callback("resetReferencePoint") { |_| reset_reference_point }
      @dialog.add_action_callback("getReferencePoint") { |_| get_reference_point_from_selection }
      @dialog.add_action_callback("reverseSpacing") { |_| reverse_spacing }
      @dialog.add_action_callback("adjustDimension") { |_, dimension, delta| adjust_dimension(dimension, delta) }
      @dialog.add_action_callback("reduceHalfDimension") { |_, dimension| reduce_half_dimension(dimension) }
      @dialog.add_action_callback("changeDirection") { |_, action| change_direction(action) }
      @dialog.add_action_callback("undoLastPlacement") { |_| undo_last_placement }
      @dialog.add_action_callback("setGroupDirection") { |_, dir| set_group_direction(dir) }
      @dialog.add_action_callback("deleteCurrentGroup") { |_| delete_current_group }
      @dialog.show
    end
    model = Sketchup.active_model
    @highlight_material = model.materials.add("Highlight")
    @highlight_material.color = Sketchup::Color.new(150, 150, 255)
    @default_material = model.materials.add("Default")
    @default_material.color = Sketchup::Color.new(255, 255, 255)
  end

  def self.create_new_group(params)
    group_id = @next_group_id
    @next_group_id += 1
    group_data = {
      id: group_id,
      length: mm_to_inch(params['length'].to_f > 0 ? params['length'].to_f : 3000.0),
      width: mm_to_inch(params['width'].to_f > 0 ? params['width'].to_f : 100.0),
      height: mm_to_inch(params['height'].to_f > 0 ? params['height'].to_f : 3000.0),
      advance_dir: params['advance_dir'],
      rotation_axis: params['rotation_axis'],
      base_spacing: mm_to_inch(params['spacing'].to_f > 0 ? params['spacing'].to_f : 3000.0),
      reference_point: @current_reference_point.to_a,
      standard_length: mm_to_inch(params['length'].to_f > 0 ? params['length'].to_f : 3000.0),
      standard_width: mm_to_inch(params['width'].to_f > 0 ? params['width'].to_f : 100.0),
      standard_height: mm_to_inch(params['height'].to_f > 0 ? params['height'].to_f : 3000.0),
      standard_spacing: mm_to_inch(params['spacing'].to_f > 0 ? params['spacing'].to_f : 3000.0)
    }
    puts "创建组: ID=#{group_id}, 长度=#{inch_to_mm(group_data[:length]).round}"
    @versions << group_data
    @current_version_index = @versions.size - 1
    create_note_components(group_data)
    save_group_to_model(group_data, group_id)
    update_panel_display
  end

  def self.update_current_group(params)
    return unless @current_version_index
    group = @versions[@current_version_index]
    group[:length] = mm_to_inch(params['length'].to_f > 0 ? params['length'].to_f : inch_to_mm(group[:length]))
    group[:width] = mm_to_inch(params['width'].to_f > 0 ? params['width'].to_f : inch_to_mm(group[:width]))
    group[:height] = mm_to_inch(params['height'].to_f > 0 ? params['height'].to_f : inch_to_mm(group[:height]))
    group[:advance_dir] = params['advance_dir']
    group[:rotation_axis] = params['rotation_axis']
    group[:base_spacing] = mm_to_inch(params['spacing'].to_f > 0 ? params['spacing'].to_f : inch_to_mm(group[:base_spacing]))
    group[:standard_length] = mm_to_inch(params['length'].to_f > 0 ? params['length'].to_f : inch_to_mm(group[:standard_length]))
    group[:standard_width] = mm_to_inch(params['width'].to_f > 0 ? params['width'].to_f : inch_to_mm(group[:standard_width]))
    group[:standard_height] = mm_to_inch(params['height'].to_f > 0 ? params['height'].to_f : inch_to_mm(group[:standard_height]))
    group[:standard_spacing] = mm_to_inch(params['spacing'].to_f > 0 ? params['spacing'].to_f : inch_to_mm(group[:standard_spacing]))
    puts "更新组: ID=#{group[:id]}, 长度=#{inch_to_mm(group[:length]).round}"
    create_note_components(group)
    save_group_to_model(group, group[:id])
    update_panel_display
  end

  def self.switch_group(direction)
    return unless @versions.any?
    old_index = @current_version_index || 0
    if direction == "prev" && @current_version_index > 0
      @current_version_index -= 1
    elsif direction == "next" && @current_version_index < @versions.size - 1
      @current_version_index += 1
    end
    group = @versions[@current_version_index]
    @current_reference_point = Geom::Point3d.new(*group[:reference_point])
    @saved_direction = group[:advance_dir] unless ["Z", "Z-"].include?(group[:advance_dir])
    puts "切换组: #{old_index} -> #{@current_version_index}"
    highlight_current_group
    update_panel_display
  end

  def self.set_reference_point(x, y, z)
    return unless @current_version_index
    @current_reference_point = Geom::Point3d.new(mm_to_inch(x.to_f), mm_to_inch(y.to_f), mm_to_inch(z.to_f))
    group = @versions[@current_version_index]
    group[:reference_point] = @current_reference_point.to_a
    save_group_to_model(group, group[:id])
    update_panel_display
  end

  def self.create_note_components(group_data)
    model = Sketchup.active_model
    definitions = model.definitions
    NOTE_TYPES.each_key do |type|
      component_name = "#{type}_v#{group_data[:id]}"
      definition = definitions[component_name] || definitions.add(component_name)
      definition.entities.clear!
      length = group_data[:length] * NOTE_FACTORS[type]
      create_rectangle(definition, length, group_data[:width], group_data[:height])
    end
  end

  def self.create_rectangle(definition, length, width, height)
    entities = definition.entities
    points = [
      [-length / 2, -width / 2, -height / 2],
      [length / 2, -width / 2, -height / 2],
      [length / 2, width / 2, -height / 2],
      [-length / 2, width / 2, -height / 2]
    ]
    face = entities.add_face(points)
    face.pushpull(height)
  end

  def self.apply_pre_rotation(instance, advance_dir, reference_point)
    case advance_dir
    when "X+", "X-"
      tr = Geom::Transformation.rotation(reference_point, [0, 0, 1], 90.degrees)
      instance.transform!(tr)
    when "Z", "Z-"
      tr = Geom::Transformation.rotation(reference_point, [0, 1, 0], 90.degrees)
      instance.transform!(tr)
    end
  end

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

    advance_reference_point
    instance = entities.add_instance(definition, @current_reference_point)
    apply_pre_rotation(instance, group[:advance_dir], @current_reference_point)

    axis = { 'X' => [1, 0, 0], 'Y' => [0, 1, 0], 'Z' => [0, 0, 1] }[group[:rotation_axis]]
    tr_rotate = Geom::Transformation.rotation(@current_reference_point, axis, angle.degrees)
    instance.transform!(tr_rotate)

    @placement_history << { instance: instance, note_type: @current_note }
    @last_action = :placement
  end

  def self.advance_reference_point
    return unless @current_version_index
    group = @versions[@current_version_index]
    spacing = group[:base_spacing].abs * NOTE_FACTORS[@current_note]
    vector = case group[:advance_dir]
             when "X+" then [spacing, 0, 0]
             when "X-" then [-spacing, 0, 0]
             when "Y+" then [0, spacing, 0]
             when "Y-" then [0, -spacing, 0]
             when "Z" then [0, 0, spacing]
             when "Z-" then [0, 0, -spacing]
             end
    @current_reference_point += vector
    group[:reference_point] = @current_reference_point.to_a
    save_group_to_model(group, group[:id])
    @last_action = :placement
    update_panel_display
  end

  def self.set_note_type(key)
    note_types = { '1' => "FN", '2' => "HN", '3' => "QN", '4' => "EN", '5' => "SN" }
    @current_note = note_types[key]
    puts "音符类型: #{@current_note}"
  end

  def self.sync_spacing
    return unless @current_version_index
    group = @versions[@current_version_index]
    group[:base_spacing] = group[:length]
    group[:standard_spacing] = group[:base_spacing].abs
    puts "同步间距: #{inch_to_mm(group[:base_spacing]).round}"
    save_group_to_model(group, group[:id])
    update_panel_display
  end

  def self.sync_width
    return unless @current_version_index
    group = @versions[@current_version_index]
    group[:width] = group[:length]
    group[:standard_width] = group[:width]
    puts "同步宽度: #{inch_to_mm(group[:width]).round}"
    create_note_components(group)
    save_group_to_model(group, group[:id])
    update_panel_display
  end

  def self.reverse_spacing
    return unless @current_version_index
    group = @versions[@current_version_index]
    group[:advance_dir] = REVERSE_DIR_MAP[group[:advance_dir]]
    group[:base_spacing] *= -1
    group[:standard_spacing] = group[:base_spacing].abs
    puts "反向间距: #{group[:advance_dir]}, #{inch_to_mm(group[:base_spacing]).round}"
    save_group_to_model(group, group[:id])
    update_panel_display
  end

  def self.adjust_dimension(dimension, delta)
    return unless @current_version_index
    group = @versions[@current_version_index]
    standard = group["standard_#{dimension}".to_sym]
    group[dimension.to_sym] += standard * delta
    puts "调整#{dimension}: #{inch_to_mm(group[dimension.to_sym]).round}"
    create_note_components(group) if %w[length width height].include?(dimension)
    save_group_to_model(group, group[:id])
    update_panel_display
  end

  def self.reduce_half_dimension(dimension)
    return unless @current_version_index
    group = @versions[@current_version_index]
    group[dimension.to_sym] /= 2.0
    group["standard_#{dimension}".to_sym] = group[dimension.to_sym]
    puts "减半#{dimension}: #{inch_to_mm(group[dimension.to_sym]).round}"
    create_note_components(group) if %w[length width height].include?(dimension)
    save_group_to_model(group, group[:id])
    update_panel_display
  end

  def self.sync_rotation_axis(group, new_dir)
    current_axis = case group[:advance_dir]
                   when "X+", "X-" then "X"
                   when "Y+", "Y-" then "Y"
                   when "Z", "Z-" then "Z"
                   end
    new_axis = case new_dir
               when "X+", "X-" then "X"
               when "Y+", "Y-" then "Y"
               when "Z", "Z-" then "Z"
               end
    group[:rotation_axis] = new_axis if group[:rotation_axis] == current_axis
  end

  def self.change_direction(action)
    return unless @current_version_index
    group = @versions[@current_version_index]
    return if ["Z", "Z-"].include?(group[:advance_dir])

    new_group = @last_action == :direction ? group : group.dup
    unless @last_action == :direction
      new_group[:id] = @next_group_id
      @next_group_id += 1
      @versions << new_group
      @current_version_index = @versions.size - 1
    end
    new_group[:reference_point] = @current_reference_point.to_a

    current_dir = group[:advance_dir]
    new_dir = action == "left" ? DIR_MAP[current_dir][0] : DIR_MAP[current_dir][1]
    new_group[:advance_dir] = new_dir
    sync_rotation_axis(new_group, new_dir)

    puts "方向切换: #{current_dir} -> #{new_dir}"
    create_note_components(new_group)
    save_group_to_model(new_group, new_group[:id])
    @last_action = :direction
    update_panel_display
  end

  def self.set_group_direction(dir)
    return unless @current_version_index
    group = @versions[@current_version_index]
    new_group = @last_action == :direction ? group : group.dup
    unless @last_action == :direction
      new_group[:id] = @next_group_id
      @next_group_id += 1
      @versions << new_group
      @current_version_index = @versions.size - 1
    end
    new_group[:advance_dir] = dir
    new_group[:reference_point] = @current_reference_point.to_a
    sync_rotation_axis(new_group, dir) if ["Z", "Z-"].include?(dir)
    puts "设置方向: #{dir}"
    create_note_components(new_group)
    save_group_to_model(new_group, new_group[:id])
    @last_action = :direction
    update_panel_display
  end

  def self.undo_last_placement
    return unless @placement_history.any?
    last = @placement_history.pop
    last[:instance].erase!
    group = @versions[@current_version_index]
    spacing = group[:base_spacing].abs * NOTE_FACTORS[last[:note_type]]
    vector = case group[:advance_dir]
             when "X+" then [-spacing, 0, 0]
             when "X-" then [spacing, 0, 0]
             when "Y+" then [0, -spacing, 0]
             when "Y-" then [0, spacing, 0]
             when "Z" then [0, 0, -spacing]
             when "Z-" then [0, 0, spacing]
             end
    @current_reference_point += vector
    group[:reference_point] = @current_reference_point.to_a
    save_group_to_model(group, group[:id])
    puts "回退音符"
    update_panel_display
  end

  def self.get_reference_point_from_selection
    model = Sketchup.active_model
    selection = model.selection
    if selection.empty? || !selection.first.is_a?(Sketchup::ComponentInstance)
      UI.messagebox("请选中一个组件")
      return
    end
    @current_reference_point = selection.first.transformation.origin
    group = @versions[@current_version_index]
    group[:reference_point] = @current_reference_point.to_a
    save_group_to_model(group, group[:id])
    update_panel_display
  end

  def self.reset_reference_point
    return unless @current_version_index
    @current_reference_point = Geom::Point3d.new(0, 0, 0)
    group = @versions[@current_version_index]
    group[:reference_point] = @current_reference_point.to_a
    save_group_to_model(group, group[:id])
    update_panel_display
  end

  def self.delete_current_group
    return unless @current_version_index
    group = @versions[@current_version_index]
    group_id = group[:id]
    model = Sketchup.active_model
    definitions = model.definitions
    NOTE_TYPES.keys.each do |type|
      def_name = "#{type}_v#{group_id}"
      definitions.remove(definitions[def_name]) if definitions[def_name]
    end
    component_name = "GroupData_#{group_id}"
    instance = model.entities.grep(Sketchup::ComponentInstance).find { |i| i.definition.name == component_name }
    model.entities.erase_entities(instance) if instance
    @versions.delete_at(@current_version_index)
    @current_version_index = @versions.empty? ? nil : [@current_version_index, @versions.size - 1].min
    puts "删除组: ID=#{group_id}"
    update_panel_display
  end

  def self.highlight_current_group
    model = Sketchup.active_model
    @versions.each_with_index do |group, index|
      material = index == @current_version_index ? @highlight_material : @default_material
      model.definitions.each do |defn|
        if defn.name.end_with?("_v#{group[:id]}")
          defn.entities.grep(Sketchup::Face).each { |face| face.material = material }
        end
      end
    end
  end

  def self.save_group_to_model(group_data, group_id)
    model = Sketchup.active_model
    component_name = "GroupData_#{group_id}"
    definition = model.definitions[component_name] || model.definitions.add(component_name)
    instance = model.entities.grep(Sketchup::ComponentInstance).find { |i| i.definition.name == component_name } ||
               model.entities.add_instance(definition, [0, 0, 0])
    instance.hidden = true
    instance.set_attribute("MusicArch", "data", group_data.to_json)
  end

  def self.load_groups_from_model
    model = Sketchup.active_model
    @versions = []
    model.entities.each do |entity|
      next unless entity.is_a?(Sketchup::ComponentInstance) && entity.definition.name.start_with?("GroupData_")
      data = entity.get_attribute("MusicArch", "data")
      next unless data
      group_data = JSON.parse(data, symbolize_names: true)
      group_data[:reference_point] = Geom::Point3d.new(*group_data[:reference_point])
      @versions << group_data
    end
    @versions.sort_by! { |g| g[:id] }
    @next_group_id = @versions.map { |g| g[:id] }.max.to_i + 1
    @current_version_index = @versions.any? ? 0 : nil
    update_panel_display if @versions.any?
  end

  def self.update_panel_display
    if @current_version_index
      group = @versions[@current_version_index]
      js = <<~JS
        document.getElementById('group_id').innerText = 'Group #{group[:id]}';
        document.getElementById('length').value = '#{inch_to_mm(group[:length]).round}';
        document.getElementById('width').value = '#{inch_to_mm(group[:width]).round}';
        document.getElementById('height').value = '#{inch_to_mm(group[:height]).round}';
        document.getElementById('advance_dir').value = '#{group[:advance_dir]}';
        document.getElementById('rotation_axis').value = '#{group[:rotation_axis]}';
        document.getElementById('spacing').value = '#{inch_to_mm(group[:base_spacing]).round}';
        document.getElementById('ref_x').value = '#{inch_to_mm(group[:reference_point].x).round}';
        document.getElementById('ref_y').value = '#{inch_to_mm(group[:reference_point].y).round}';
        document.getElementById('ref_z').value = '#{inch_to_mm(group[:reference_point].z).round}';
      JS
      @dialog.execute_script(js)
    else
      js = <<~JS
        document.getElementById('group_id').innerText = '未选择';
        document.getElementById('length').value = '3000';
        document.getElementById('width').value = '100';
        document.getElementById('height').value = '3000';
        document.getElementById('advance_dir').value = 'X+';
        document.getElementById('rotation_axis').value = 'Z';
        document.getElementById('spacing').value = '3000';
        document.getElementById('ref_x').value = '0';
        document.getElementById('ref_y').value = '0';
        document.getElementById('ref_z').value = '0';
      JS
      @dialog.execute_script(js)
    end
  end

  def self.get_html_content
    <<~HTML
      <html>
      <body>
        <h2>Music Architecture 面板</h2>
        <p>当前组: <span id="group_id">未选择</span></p>
        <button onclick="loadGroups()">读取组数据</button>
        <button onclick="deleteCurrentGroup()">删除当前组</button>
        <form id="paramsForm">
          <label>长度 (mm): <input type="number" id="length" value="3000"></label><br>
          <label>宽度 (mm): <input type="number" id="width" value="100"></label><br>
          <label>高度 (mm): <input type="number" id="height" value="3000"></label><br>
          <label>行进方向:
            <input type="text" id="advance_dir" value="X+" readonly style="width: 50px;">
            <button type="button" onclick="setDirection('X+')">X+</button>
            <button type="button" onclick="setDirection('Y+')">Y+</button>
            <button type="button" onclick="setDirection('X-')">X-</button>
            <button type="button" onclick="setDirection('Y-')">Y-</button>
            <button type="button" onclick="setDirection('Z')">Z</button>
            <button type="button" onclick="setDirection('Z-')">Z-</button>
          </label><br>
          <label>旋转轴:
            <input type="text" id="rotation_axis" value="Z" readonly style="width: 30px;">
            <button type="button" onclick="setRotationAxis('X')">X</button>
            <button type="button" onclick="setRotationAxis('Y')">Y</button>
            <button type="button" onclick="setRotationAxis('Z')">Z</button>
          </label><br>
          <label>标准间距 (mm): <input type="number" id="spacing" value="3000"></label><br>
          <button type="button" onclick="createNewGroup()">创建新组</button>
          <button type="button" onclick="updateCurrentGroup()">保存到当前组</button>
          <button type="button" onclick="syncSpacing()">同步间距与长度</button>
          <button type="button" onclick="syncWidth()">同步宽度与长度</button>
          <button type="button" onclick="reverseSpacing()">反向间距</button>
          <button type="button" onclick="adjustDimension('length', 1)">+1倍长度</button>
          <button type="button" onclick="adjustDimension('length', -1)">-1倍长度</button>
          <button type="button" onclick="reduceHalfDimension('length')">长度减半</button>
          <button type="button" onclick="adjustDimension('width', 1)">+1倍宽度</button>
          <button type="button" onclick="adjustDimension('width', -1)">-1倍宽度</button>
          <button type="button" onclick="reduceHalfDimension('width')">宽度减半</button>
          <button type="button" onclick="adjustDimension('height', 1)">+1倍高度</button>
          <button type="button" onclick="adjustDimension('height', -1)">-1倍高度</button>
          <button type="button" onclick="reduceHalfDimension('height')">高度减半</button>
          <button type="button" onclick="adjustDimension('base_spacing', 1)">+1倍间距</button>
          <button type="button" onclick="adjustDimension('base_spacing', -1)">-1倍间距</button>
          <button type="button" onclick="reduceHalfDimension('base_spacing')">间距减半</button>
          <button type="button" onclick="changeDirection('left')">左转</button>
          <button type="button" onclick="changeDirection('right')">右转</button>
          <button type="button" onclick="undoLastPlacement()">回退</button>
        </form>
        <h3>当前参考点 (mm)</h3>
        <p>X: <input type="number" id="ref_x" value="0"></p>
        <p>Y: <input type="number" id="ref_y" value="0"></p>
        <p>Z: <input type="number" id="ref_z" value="0"></p>
        <button onclick="updateReferencePoint()">更新参考点</button>
        <button onclick="resetReferencePoint()">重置参考点</button>
        <button onclick="getReferencePoint()">获取参考点</button>
        <button onclick="switchGroup('prev')">前一组</button>
        <button onclick="switchGroup('next')">后一组</button>
        <h3>放置音符</h3>
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
        <h3>选择音符类型</h3>
        <button onclick="setNoteType('1')">FN (全音符)</button>
        <button onclick="setNoteType('2')">HN (二分音符)</button>
        <button onclick="setNoteType('3')">QN (四分音符)</button>
        <button onclick="setNoteType('4')">EN (八分音符)</button>
        <button onclick="setNoteType('5')">SN (十六分音符)</button>
        <h3>空拍</h3>
        <button onclick="advanceReferencePoint()">空拍 (0)</button>
      </body>
      <script>
        window.onload = function() {
          document.body.focus();
          console.log("对话框已加载，尝试获取焦点");
        };

        document.addEventListener('keydown', function(e) {
          var key = e.key;
          var validKeys = ['z', 's', 'x', 'd', 'c', 'v', 'g', 'b', 'h', 'n', 'j', 'm', '0', ' ', '1', '2', '3', '4', '5', 
                           'ArrowLeft', 'ArrowRight', 'ArrowUp', 'ArrowDown', '[', ']', '\\\\', 'l', ';', '\\'', ',', '.', '/', 'p', '-', '+', '=', 'o', 'Backspace'];
          if (validKeys.includes(key) && e.target.tagName !== 'INPUT' && e.target.tagName !== 'TEXTAREA') {
            console.log("捕获按键: " + key);
            if (key === '0' || key === ' ') {
              sketchup.advanceReferencePoint();
            } else if (['1', '2', '3', '4', '5'].includes(key)) {
              sketchup.setNoteType(key);
            } else if (key === 'ArrowLeft') {
              sketchup.changeDirection('left');
            } else if (key === 'ArrowRight') {
              sketchup.changeDirection('right');
            } else if (key === 'ArrowUp') {
              toggleZDirection(true);
            } else if (key === 'ArrowDown') {
              toggleZDirection(false);
            } else if (key === '[') {
              sketchup.reduceHalfDimension('length');
            } else if (key === ']') {
              sketchup.adjustDimension('length', -1);
            } else if (key === '\\\\') {
              sketchup.adjustDimension('length', 1);
            } else if (key === 'l') {
              sketchup.reduceHalfDimension('width');
            } else if (key === ';') {
              sketchup.adjustDimension('width', -1);
            } else if (key === '\\'') {
              sketchup.adjustDimension('width', 1);
            } else if (key === ',') {
              sketchup.reduceHalfDimension('height');
            } else if (key === '.') {
              sketchup.adjustDimension('height', -1);
            } else if (key === '/') {
              sketchup.adjustDimension('height', 1);
            } else if (key === 'p') {
              sketchup.syncSpacing();
            } else if (key === '-') {
              sketchup.switchGroup('prev');
            } else if (key === '+' || key === '=') {
              sketchup.switchGroup('next');
            } else if (key === 'o') {
              sketchup.syncWidth();
            } else if (key === 'Backspace') {
              sketchup.undoLastPlacement();
            } else {
              sketchup.placeNote(key);
            }
            e.preventDefault();
            e.stopPropagation();
          }
        });

        document.addEventListener('click', function() {
          document.body.focus();
          console.log("对话框被点击，已重新获取焦点");
        });

        function toggleZDirection(isPositive) {
          var currentDir = document.getElementById('advance_dir').value;
          var targetDir = isPositive ? 'Z' : 'Z-';
          if (currentDir === 'Z' || currentDir === 'Z-') {
            sketchup.setGroupDirection(window.savedDirection || 'X+');
          } else {
            window.savedDirection = currentDir;
            sketchup.setGroupDirection(targetDir);
          }
        }

        function createNewGroup() { sketchup.createNewGroup(getParams()); }
        function updateCurrentGroup() { sketchup.updateCurrentGroup(getParams()); }
        function switchGroup(direction) { sketchup.switchGroup(direction); }
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
        function syncWidth() { sketchup.syncWidth(); }
        function loadGroups() { sketchup.loadGroups(); }
        function resetReferencePoint() { sketchup.resetReferencePoint(); }
        function getReferencePoint() { sketchup.getReferencePoint(); }
        function reverseSpacing() { sketchup.reverseSpacing(); }
        function adjustDimension(dimension, delta) { sketchup.adjustDimension(dimension, delta); }
        function reduceHalfDimension(dimension) { sketchup.reduceHalfDimension(dimension); }
        function changeDirection(action) { sketchup.changeDirection(action); }
        function undoLastPlacement() { sketchup.undoLastPlacement(); }
        function setDirection(dir) { sketchup.setGroupDirection(dir); }
        function setRotationAxis(axis) { document.getElementById('rotation_axis').value = axis; }
        function deleteCurrentGroup() { sketchup.deleteCurrentGroup(); }
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