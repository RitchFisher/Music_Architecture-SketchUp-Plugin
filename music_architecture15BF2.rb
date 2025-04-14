require 'sketchup.rb'
require 'json'

module MusicArchitecture
  DEFAULTS = { length: 3000.0, width: 100.0, height: 3000.0, spacing: 3000.0 }.freeze
  DIRECTION_VECTORS = {
    "X+" => [1, 0, 0], "X-" => [-1, 0, 0],
    "Y+" => [0, 1, 0], "Y-" => [0, -1, 0],
    "Z" => [0, 0, 1], "Z-" => [0, 0, -1]
  }.freeze
  NOTE_FACTORS = { "FN" => 1.0, "HN" => 0.5, "QN" => 0.25, "EN" => 0.125, "SN" => 0.0625 }.freeze
  NOTE_TYPES = { "FN" => "全音符", "HN" => "二分音符", "QN" => "四分音符", "EN" => "八分音符", "SN" => "十六分音符" }.freeze

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
  @guide_line = nil

  def self.mm_to_inch(mm)
    mm / 25.4
  end

  def self.inch_to_mm(inch)
    inch * 25.4
  end

  unless file_loaded?(__FILE__)
    UI.menu('Plugins').add_item('Show Music Architecture Panel') { show_panel }
    file_loaded(__FILE__)
  end

  def self.show_panel
    unless @dialog&.visible?
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
      register_callbacks
      @dialog.show
    end
    model = Sketchup.active_model
    @highlight_material = model.materials.add("Highlight").tap { |m| m.color = [150, 150, 255] }
    @default_material = model.materials.add("Default").tap { |m| m.color = [255, 255, 255] }
  end

  def self.register_callbacks
    {
      "createNewGroup" => ->(params) { create_new_group(params) },
      "updateCurrentGroup" => ->(params) { update_current_group(params) },
      "switchGroup" => ->(direction) { switch_group(direction) },
      "setReferencePoint" => ->(x, y, z) { set_reference_point(x, y, z) },
      "placeNote" => ->(key) { place_note(key) },
      "setNoteType" => ->(key) { set_note_type(key) },
      "advanceReferencePoint" => -> { advance_reference_point },
      "syncSpacing" => -> { sync_spacing },
      "syncWidth" => -> { sync_width },
      "loadGroups" => -> { load_groups_from_model },
      "resetReferencePoint" => -> { reset_reference_point },
      "getReferencePoint" => -> { get_reference_point_from_selection },
      "reverseSpacing" => -> { reverse_spacing },
      "adjustDimension" => ->(dimension, delta) { adjust_dimension(dimension, delta) },
      "reduceHalfDimension" => ->(dimension) { reduce_half_dimension(dimension) },
      "changeDirection" => ->(action) { update_direction(action == "left" ? 0 : 1) },
      "undoLastPlacement" => -> { undo_last_placement },
      "setGroupDirection" => ->(dir) { update_direction(dir) },
      "deleteCurrentGroup" => -> { delete_current_group }
    }.each { |name, proc| @dialog.add_action_callback(name) { |_, *args| proc.call(*args) } }
  end

  def self.create_new_group(params)
    group_id = (@versions.map { |g| g[:id].to_i }.max || 0) + 1
    group_data = {
      id: group_id,
      reference_point: @current_reference_point.to_a,
      advance_dir: params['advance_dir'] || "X+",
      rotation_axis: params['rotation_axis'] || "Z"
    }
    update_group_data(group_data, params)
    @versions << group_data
    @current_version_index = @versions.size - 1
    create_note_components(group_data)
    save_group_to_model(group_data)
    update_guide_line
    update_panel_display
    puts "创建组：ID=#{group_id}, 长度=#{inch_to_mm(group_data[:length])}, 间距=#{inch_to_mm(group_data[:base_spacing])}"
  end

  def self.update_current_group(params)
    return unless @current_version_index
    group = @versions[@current_version_index]
    update_group_data(group, params)
    create_note_components(group)
    save_group_to_model(group)
    update_guide_line
    update_panel_display
    puts "更新组：长度=#{inch_to_mm(group[:length])}, 间距=#{inch_to_mm(group[:base_spacing])}"
  end

  def self.update_group_data(group, params)
    group.merge!(
      length: mm_to_inch(params['length'].to_f > 0 ? params['length'].to_f : (inch_to_mm(group[:length]) || DEFAULTS[:length])),
      width: mm_to_inch(params['width'].to_f > 0 ? params['width'].to_f : (inch_to_mm(group[:width]) || DEFAULTS[:width])),
      height: mm_to_inch(params['height'].to_f > 0 ? params['height'].to_f : (inch_to_mm(group[:height]) || DEFAULTS[:height])),
      base_spacing: mm_to_inch(params['spacing'].to_f > 0 ? params['spacing'].to_f : (inch_to_mm(group[:base_spacing]) || DEFAULTS[:spacing])),
      standard_length: mm_to_inch(params['length'].to_f > 0 ? params['length'].to_f : (inch_to_mm(group[:length]) || DEFAULTS[:length])),
      standard_width: mm_to_inch(params['width'].to_f > 0 ? params['width'].to_f : (inch_to_mm(group[:width]) || DEFAULTS[:width])),
      standard_height: mm_to_inch(params['height'].to_f > 0 ? params['height'].to_f : (inch_to_mm(group[:height]) || DEFAULTS[:height])),
      standard_spacing: mm_to_inch(params['spacing'].to_f > 0 ? params['spacing'].to_f : (inch_to_mm(group[:base_spacing]) || DEFAULTS[:spacing]))
    )
  end

  def self.switch_group(direction)
    return unless @current_version_index
    new_index = @current_version_index + (direction == "prev" ? -1 : 1)
    return unless (0...@versions.size).include?(new_index)
    @current_version_index = new_index
    group = @versions[@current_version_index]
    @current_reference_point = Geom::Point3d.new(*group[:reference_point])
    @saved_direction = group[:advance_dir] unless ["Z", "Z-"].include?(group[:advance_dir])
    highlight_current_group
    update_guide_line
    update_panel_display
    puts "切换到组：ID=#{group[:id]}, 方向=#{group[:advance_dir]}"
  end

  def self.set_reference_point(x, y, z)
    return unless @current_version_index
    @current_reference_point = Geom::Point3d.new(mm_to_inch(x.to_f), mm_to_inch(y.to_f), mm_to_inch(z.to_f))
    group = @versions[@current_version_index]
    group[:reference_point] = @current_reference_point.to_a
    save_group_to_model(group)
    update_guide_line
    update_panel_display
  end

  def self.create_note_components(group_data)
    model = Sketchup.active_model
    definitions = model.definitions
    NOTE_FACTORS.each do |type, factor|
      definition = definitions["#{type}_v#{group_data[:id]}"] || definitions.add("#{type}_v#{group_data[:id]}")
      definition.entities.clear!
      create_rectangle(definition, group_data[:length] * factor, group_data[:width], group_data[:height])
    end
  end

  def self.create_rectangle(definition, length, width, height)
    entities = definition.entities
    points = [
      [-length/2, -width/2, -height/2],
      [length/2, -width/2, -height/2],
      [length/2, width/2, -height/2],
      [-length/2, width/2, -height/2]
    ]
    entities.add_face(points).pushpull(height)
  end

  def self.place_note(key)
    return unless @current_version_index
    group = @versions[@current_version_index]
    note_map = { 'z' => 0, 's' => 15, 'x' => 30, 'd' => 45, 'c' => 60, 'v' => 75,
                 'g' => 90, 'b' => 105, 'h' => 120, 'n' => 135, 'j' => 150, 'm' => 165 }
    angle = note_map[key]
    model = Sketchup.active_model
    definition = model.definitions["#{@current_note}_v#{group[:id]}"]
    
    advance_reference_point
    instance = model.active_entities.add_instance(definition, @current_reference_point)

    case group[:advance_dir]
    when "X+", "X-" then instance.transform!(Geom::Transformation.rotation(@current_reference_point, [0, 0, 1], 90.degrees))
    when "Z", "Z-" then instance.transform!(Geom::Transformation.rotation(@current_reference_point, [0, 1, 0], 90.degrees))
    end

    axis = { 'X' => [1, 0, 0], 'Y' => [0, 1, 0], 'Z' => [0, 0, 1] }[group[:rotation_axis]]
    instance.transform!(Geom::Transformation.rotation(@current_reference_point, axis, angle.degrees))

    @placement_history << { instance: instance, note_type: @current_note }
    @last_action = :placement
    update_guide_line
  end

  def self.advance_reference_point
    return unless @current_version_index
    group = @versions[@current_version_index]
    spacing = group[:base_spacing].abs * NOTE_FACTORS[@current_note]
    vector = DIRECTION_VECTORS[group[:advance_dir]].map { |v| v * spacing }
    @current_reference_point += Geom::Vector3d.new(vector)
    group[:reference_point] = @current_reference_point.to_a
    save_group_to_model(group)
    @last_action = :placement
    update_guide_line
    update_panel_display
    puts "间距计算：base_spacing=#{inch_to_mm(group[:base_spacing])}, note=#{@current_note}, spacing=#{inch_to_mm(spacing)}"
  end

  def self.update_guide_line
    return unless @current_version_index
    model = Sketchup.active_model
    entities = model.active_entities
    
    @guide_line&.valid? && entities.erase_entities(@guide_line)
    group = @versions[@current_version_index]
    spacing = group[:base_spacing].abs * NOTE_FACTORS[@current_note]
    vector = DIRECTION_VECTORS[group[:advance_dir]].map { |v| v * spacing }
    end_point = @current_reference_point + Geom::Vector3d.new(vector)
    @guide_line = entities.add_cline(@current_reference_point, end_point)
    puts "绘制虚线：从 #{@current_reference_point.to_a.map { |x| inch_to_mm(x).round }} 到 #{end_point.to_a.map { |x| inch_to_mm(x).round }}"
  end

  def self.set_note_type(key)
    @current_note = { '1' => "FN", '2' => "HN", '3' => "QN", '4' => "EN", '5' => "SN" }[key]
    update_guide_line
    puts "设置音符类型：#{@current_note}"
  end

  def self.sync_spacing
    return unless @current_version_index
    group = @versions[@current_version_index]
    group[:base_spacing] = group[:length]
    group[:standard_spacing] = group[:base_spacing].abs
    save_group_to_model(group)
    update_guide_line
    update_panel_display
    puts "同步间距：长度=#{inch_to_mm(group[:length])}, 间距=#{inch_to_mm(group[:base_spacing])}"
  end

  def self.sync_width
    return unless @current_version_index
    group = @versions[@current_version_index]
    group[:width] = group[:length]
    group[:standard_width] = group[:width]
    create_note_components(group)
    save_group_to_model(group)
    update_guide_line
    update_panel_display
    puts "同步宽度：宽度=#{inch_to_mm(group[:width])}, 长度=#{inch_to_mm(group[:length])}"
  end

  def self.reverse_spacing
    return unless @current_version_index
    group = @versions[@current_version_index]
    dir_map = { "X+" => "X-", "X-" => "X+", "Y+" => "Y-", "Y-" => "Y+", "Z" => "Z", "Z-" => "Z-" }
    group[:advance_dir] = dir_map[group[:advance_dir]]
    group[:base_spacing] *= -1
    group[:standard_spacing] = group[:base_spacing].abs
    save_group_to_model(group)
    update_guide_line
    update_panel_display
    puts "反向间距：方向=#{group[:advance_dir]}, 间距=#{inch_to_mm(group[:base_spacing])}"
  end

  def self.adjust_dimension(dimension, delta)
    return unless @current_version_index
    group = @versions[@current_version_index]
    group[dimension.to_sym] += group["standard_#{dimension}".to_sym] * delta
    create_note_components(group) if %w[length width height].include?(dimension)
    save_group_to_model(group)
    update_guide_line
    update_panel_display
    puts "调整#{dimension}：#{inch_to_mm(group[dimension.to_sym])}, 标准值：#{inch_to_mm(group["standard_#{dimension}".to_sym])}"
  end

  def self.reduce_half_dimension(dimension)
    return unless @current_version_index
    group = @versions[@current_version_index]
    group[dimension.to_sym] /= 2.0
    group["standard_#{dimension}".to_sym] = group[dimension.to_sym]
    create_note_components(group) if %w[length width height].include?(dimension)
    save_group_to_model(group)
    update_guide_line
    update_panel_display
    puts "减半#{dimension}：#{inch_to_mm(group[dimension.to_sym])}, 新标准值：#{inch_to_mm(group["standard_#{dimension}".to_sym])}"
  end

  def self.update_direction(target)
    return unless @current_version_index
    group = @versions[@current_version_index]
    new_group = @last_action == :direction ? group : group.dup.tap { |g| g[:id] = (@versions.map { |v| v[:id].to_i }.max || 0) + 1 }
    @versions << new_group unless @last_action == :direction
    @current_version_index = @versions.size - 1 if new_group != group
    new_group[:reference_point] = @current_reference_point.to_a

    dir_map = { "X+" => ["Y+", "Y-"], "Y+" => ["X-", "X+"], "X-" => ["Y-", "Y+"], "Y-" => ["X+", "X-"], "Z" => ["Z"], "Z-" => ["Z-"] }
    new_dir = target.is_a?(String) ? target : dir_map[group[:advance_dir]][target]
    new_group[:advance_dir] = new_dir

    unless ["Z", "Z-"].include?(new_dir)
      current_axis = group[:advance_dir][0] == 'X' ? 'X' : 'Y'
      new_axis = new_dir[0] == 'X' ? 'X' : 'Y'
      new_group[:rotation_axis] = new_axis if group[:rotation_axis] == current_axis
    else
      new_group[:rotation_axis] = "Z" if group[:rotation_axis] == { "X+" => "X", "X-" => "X", "Y+" => "Y", "Y-" => "Y" }[group[:advance_dir]]
    end

    create_note_components(new_group)
    save_group_to_model(new_group)
    @last_action = :direction
    update_guide_line
    update_panel_display
    puts "方向更新：#{group[:advance_dir]} -> #{new_dir}, 组ID：#{new_group[:id]}"
  end

  def self.undo_last_placement
    return unless @placement_history.any?
    last = @placement_history.pop
    last[:instance].erase!
    group = @versions[@current_version_index]
    spacing = group[:base_spacing].abs * NOTE_FACTORS[last[:note_type]]
    vector = DIRECTION_VECTORS[group[:advance_dir]].map { |v| -v * spacing }
    @current_reference_point += Geom::Vector3d.new(vector)
    group[:reference_point] = @current_reference_point.to_a
    save_group_to_model(group)
    update_guide_line
    update_panel_display
    puts "回退音符"
  end

  def self.get_reference_point_from_selection
    model = Sketchup.active_model
    selection = model.selection
    unless selection.first&.is_a?(Sketchup::ComponentInstance)
      UI.messagebox("请选中一个组件")
      return
    end
    @current_reference_point = selection.first.transformation.origin
    group = @versions[@current_version_index]
    group[:reference_point] = @current_reference_point.to_a
    save_group_to_model(group)
    update_guide_line
    update_panel_display
  end

  def self.reset_reference_point
    return unless @current_version_index
    @current_reference_point = Geom::Point3d.new(0, 0, 0)
    group = @versions[@current_version_index]
    group[:reference_point] = @current_reference_point.to_a
    save_group_to_model(group)
    update_guide_line
    update_panel_display
  end

  def self.delete_current_group
    return unless @current_version_index
    group = @versions[@current_version_index]
    model = Sketchup.active_model
    %w[FN HN QN EN SN].each { |type| model.definitions.remove(model.definitions["#{type}_v#{group[:id]}"]) }
    instance = model.entities.grep(Sketchup::ComponentInstance).find { |i| i.definition.name == "GroupData_#{group[:id]}" }
    model.entities.erase_entities(instance) if instance
    @versions.delete_at(@current_version_index)
    if @versions.empty?
      @current_version_index = @saved_direction = @guide_line = nil
    elsif @current_version_index >= @versions.size
      @current_version_index = @versions.size - 1
    end
    update_guide_line
    update_panel_display
    puts "删除组：ID=#{group[:id]}"
  end

  def self.highlight_current_group
    model = Sketchup.active_model
    @versions.each_with_index do |group, index|
      material = index == @current_version_index ? @highlight_material : @default_material
      model.definitions.each do |defn|
        defn.entities.grep(Sketchup::Face).each { |face| face.material = material } if defn.name.end_with?("_v#{group[:id]}")
      end
    end
  end

  def self.save_group_to_model(group_data)
    model = Sketchup.active_model
    component_name = "GroupData_#{group_data[:id]}"
    definition = model.definitions[component_name] || model.definitions.add(component_name)
    instance = model.entities.grep(Sketchup::ComponentInstance).find { |i| i.definition.name == component_name } ||
               model.entities.add_instance(definition, [0, 0, 0])
    instance.hidden = true
    instance.set_attribute("MusicArch", "data", group_data.to_json)
  end

  def self.load_groups_from_model
    @versions = Sketchup.active_model.entities.grep(Sketchup::ComponentInstance)
      .select { |e| e.definition.name.start_with?("GroupData_") }
      .map { |e| JSON.parse(e.get_attribute("MusicArch", "data") || "{}", symbolize_names: true) }
      .reject { |g| g.empty? }
      .each { |g| g[:reference_point] = Geom::Point3d.new(*g[:reference_point]) }
      .sort_by { |g| g[:id].to_i }
    @current_version_index = @versions.any? ? 0 : nil
    @saved_direction = nil
    update_guide_line if @current_version_index
    update_panel_display if @versions.any?
    puts "加载组：共 #{@versions.size} 个，ID列表：#{@versions.map { |g| g[:id] }.join(', ')}"
  end

  def self.update_panel_display
    if @current_version_index
      group = @versions[@current_version_index]
      @dialog.execute_script("document.getElementById('group_id').innerText = '组 #{group[:id]}';")
      { 'length' => :length, 'width' => :width, 'height' => :height, 'spacing' => :base_spacing }.each do |id, key|
        @dialog.execute_script("document.getElementById('#{id}').value = '#{inch_to_mm(group[key]).round}';")
      end
      @dialog.execute_script("document.getElementById('advance_dir').value = '#{group[:advance_dir]}';")
      @dialog.execute_script("document.getElementById('rotation_axis').value = '#{group[:rotation_axis]}';")
      %w[x y z].each_with_index do |axis, i|
        @dialog.execute_script("document.getElementById('ref_#{axis}').value = '#{inch_to_mm(group[:reference_point][i]).round}';")
      end
    else
      @dialog.execute_script("document.getElementById('group_id').innerText = '未选择';")
      @dialog.execute_script("document.getElementById('length').value = '#{DEFAULTS[:length]}';")
      @dialog.execute_script("document.getElementById('width').value = '#{DEFAULTS[:width]}';")
      @dialog.execute_script("document.getElementById('height').value = '#{DEFAULTS[:height]}';")
      @dialog.execute_script("document.getElementById('spacing').value = '#{DEFAULTS[:spacing]}';")
      @dialog.execute_script("document.getElementById('advance_dir').value = 'X+';")
      @dialog.execute_script("document.getElementById('rotation_axis').value = 'Z';")
      %w[ref_x ref_y ref_z].each { |id| @dialog.execute_script("document.getElementById('#{id}').value = '0';") }
    end
  end

  def self.get_html_content
    <<~HTML
      <html>
      <body>
        <h2>Music Architecture Panel</h2>
        <p>当前组: <span id="group_id">未选择</span></p>
        <button onclick="loadGroups()">读取组数据</button>
        <button onclick="deleteCurrentGroup()">删除当前组</button>
        <form id="paramsForm">
          <label>长度 (mm): <input type="number" id="length" value="#{DEFAULTS[:length]}"></label><br>
          <label>宽度 (mm): <input type="number" id="width" value="#{DEFAULTS[:width]}"></label><br>
          <label>高度 (mm): <input type="number" id="height" value="#{DEFAULTS[:height]}"></label><br>
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
          <label>标准间距 (mm): <input type="number" id="spacing" value="#{DEFAULTS[:spacing]}"></label><br>
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
        <button onclick="setNoteType('1')">全音符</button>
        <button onclick="setNoteType('2')">二分音符</button>
        <button onclick="setNoteType('3')">四分音符</button>
        <button onclick="setNoteType('4')">八分音符</button>
        <button onclick="setNoteType('5')">十六分音符</button>
        <h3>空拍</h3>
        <button onclick="advanceReferencePoint()">空拍 (0)</button>
      </body>
      <script>
        window.onload = () => document.body.focus();
        document.addEventListener('click', () => document.body.focus());

        document.addEventListener('keydown', e => {
          const key = e.key;
          const validKeys = ['z', 's', 'x', 'd', 'c', 'v', 'g', 'b', 'h', 'n', 'j', 'm', '0', ' ', '1', '2', '3', '4', '5',
                             'ArrowLeft', 'ArrowRight', 'ArrowUp', 'ArrowDown', '[', ']', '\\\\', 'l', ';', '\\'', ',', '.', '/', 'p', '-', '+', '=', 'o', 'Backspace'];
          if (validKeys.includes(key) && e.target.tagName !== 'INPUT' && e.target.tagName !== 'TEXTAREA') {
            const actions = {
              '0': () => sketchup.advanceReferencePoint(),
              ' ': () => sketchup.advanceReferencePoint(),
              '1': () => sketchup.setNoteType('1'),
              '2': () => sketchup.setNoteType('2'),
              '3': () => sketchup.setNoteType('3'),
              '4': () => sketchup.setNoteType('4'),
              '5': () => sketchup.setNoteType('5'),
              'ArrowLeft': () => sketchup.changeDirection('left'),
              'ArrowRight': () => sketchup.changeDirection('right'),
              'ArrowUp': toggleZDirection,
              'ArrowDown': toggleZNegativeDirection,
              '[': () => sketchup.reduceHalfDimension('length'),
              ']': () => sketchup.adjustDimension('length', -1),
              '\\\\': () => sketchup.adjustDimension('length', 1),
              'l': () => sketchup.reduceHalfDimension('width'),
              ';': () => sketchup.adjustDimension('width', -1),
              '\'': () => sketchup.adjustDimension('width', 1),
              ',': () => sketchup.reduceHalfDimension('height'),
              '.': () => sketchup.adjustDimension('height', -1),
              '/': () => sketchup.adjustDimension('height', 1),
              'p': () => sketchup.syncSpacing(),
              '-': () => sketchup.switchGroup('prev'),
              '+': () => sketchup.switchGroup('next'),
              '=': () => sketchup.switchGroup('next'),
              'o': () => sketchup.syncWidth(),
              'Backspace': () => sketchup.undoLastPlacement()
            };
            (actions[key] || (() => sketchup.placeNote(key)))();
            e.preventDefault();
            e.stopPropagation();
          }
        });

        function toggleZDirection() {
          const currentDir = document.getElementById('advance_dir').value;
          sketchup.setGroupDirection(currentDir === 'Z' ? (window.savedDirection || 'X+') : (window.savedDirection = currentDir, 'Z'));
        }

        function toggleZNegativeDirection() {
          const currentDir = document.getElementById('advance_dir').value;
          sketchup.setGroupDirection(currentDir === 'Z-' ? (window.savedDirection || 'X+') : (window.savedDirection = currentDir, 'Z-'));
        }

        function createNewGroup() { sketchup.createNewGroup(getParams()); }
        function updateCurrentGroup() { sketchup.updateCurrentGroup(getParams()); }
        function updateReferencePoint() {
          sketchup.setReferencePoint(
            document.getElementById('ref_x').value,
            document.getElementById('ref_y').value,
            document.getElementById('ref_z').value
          );
        }
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
        function switchGroup(direction) { sketchup.switchGroup(direction); }
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
      </script>
      </html>
    HTML
  end
end