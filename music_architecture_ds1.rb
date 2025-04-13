# music_architecture4.rb
require 'sketchup.rb'
require 'json'

module MusicArchitecture
  @versions = []
  @current_version_index = nil
  @current_note = "FN"
  @dialog = nil

  NOTE_TYPES = {
    "FN" => "Full Note",
    "HN" => "Half Note",
    "QN" => "Quarter Note",
    "EN" => "Eighth Note",
    "SN" => "Sixteenth Note"
  }

  unless file_loaded?(__FILE__)
    menu = UI.menu('Plugins')
    menu.add_item('Show Music Architecture Panel') { show_panel }
    file_loaded(__FILE__)
  end

  def self.show_panel
    return if @dialog&.visible?
    
    @dialog = UI::HtmlDialog.new(
      dialog_title: "Music Architecture",
      preferences_key: "MusicArchitecturePanel",
      width: 400,
      height: 600,
      resizable: true
    )
    
    @dialog.set_html(get_html_content)
    setup_callbacks
    @dialog.show
    @dialog.bring_to_front
    load_groups_from_model
    update_panel_display if @versions.any?
  end

  private

  def self.setup_callbacks
    @dialog.add_action_callback("createNewGroup") { |_, params| create_new_group(params) }
    @dialog.add_action_callback("updateCurrentGroup") { |_, params| update_current_group(params) }
    @dialog.add_action_callback("switchGroup") { |_, direction| switch_group(direction) }
    @dialog.add_action_callback("setReferencePoint") { |_, x, y, z| set_reference_point(x, y, z) }
    @dialog.add_action_callback("placeNote") { |_, key| place_note(key) }
    @dialog.add_action_callback("setNoteType") { |_, key| set_note_type(key) }
    @dialog.add_action_callback("advanceReferencePoint") { |_| advance_reference_point }
  end

  def self.create_new_group(params)
    group_id = @versions.size + 1
    group_data = {
      id: group_id,
      length: params['length'].to_f,
      width: params['width'].to_f,
      height: params['height'].to_f,
      advance_dir: params['advance_dir'].upcase,
      rotation_axis: params['rotation_axis'].upcase,
      base_spacing: params['spacing'].to_f,
      reference_point: @versions.last ? @versions.last[:reference_point] : [0, 0, 0]
    }
    @versions << group_data
    @current_version_index = @versions.size - 1
    create_note_components(group_data)
    save_group_to_model(group_data, group_id)
    update_panel_display
  end

  def self.update_current_group(params)
    return unless @current_version_index
    
    group = @versions[@current_version_index]
    %i[length width height advance_dir rotation_axis base_spacing].each do |key|
      group[key] = params[key.to_s].to_f rescue group[key]
    end
    create_note_components(group)
    save_group_to_model(group, group[:id])
    update_panel_display
  end

  def self.switch_group(direction)
    return unless @current_version_index
    
    new_index = case direction
                when "prev" then [@current_version_index - 1, 0].max
                when "next" then [@current_version_index + 1, @versions.size - 1].min
                end
    @current_version_index = new_index if new_index != @current_version_index
    update_panel_display
  end

  def self.set_reference_point(x, y, z)
    return unless @current_version_index
    
    @versions[@current_version_index][:reference_point] = [x.to_f, y.to_f, z.to_f]
    save_group_to_model(@versions[@current_version_index], @versions[@current_version_index][:id])
    update_panel_display
  end

  def self.create_note_components(group_data)
    model = Sketchup.active_model
    definitions = model.definitions
    note_types = { "FN" => 1.0, "HN" => 0.5, "QN" => 0.25, "EN" => 0.125, "SN" => 0.0625 }
    
    note_types.each do |type, factor|
      component_name = "#{type}_v#{group_data[:id]}"
      definition = definitions[component_name] || definitions.add(component_name)
      definition.entities.clear!
      create_rectangle(definition, group_data[:length] * factor, group_data[:width], group_data[:height])
    end
  end

  def self.create_rectangle(definition, length, width, height)
    half = [length/2, width/2, height/2]
    points = [
      [-half[0], -half[1], -half[2]],
      [half[0], -half[1], -half[2]],
      [half[0], half[1], -half[2]],
      [-half[0], half[1], -half[2]]
    ]
    face = definition.entities.add_face(points)
    face.pushpull(height)
  end

  def self.place_note(key)
    return unless @current_version_index
    
    group = @versions[@current_version_index]
    note_map = {
      'z' => 0, 's' => 15, 'x' => 30, 'd' => 45,
      'c' => 60, 'v' => 75, 'g' => 90, 'b' => 105,
      'h' => 120, 'n' => 135, 'j' => 150, 'm' => 165
    }
    return unless note_map.key?(key)
    
    model = Sketchup.active_model
    component_name = "#{@current_note}_v#{group[:id]}"
    return unless model.definitions[component_name]
    
    reference_point = Geom::Point3d.new(*group[:reference_point])
    instance = model.active_entities.add_instance(model.definitions[component_name], reference_point)
    
    axis = case group[:rotation_axis]
           when 'X' then [1, 0, 0]
           when 'Y' then [0, 1, 0]
           else [0, 0, 1]
           end
    rotation = Geom::Transformation.rotation(reference_point, axis, note_map[key].degrees)
    instance.transform!(rotation)
    
    advance_reference_point
  end

  def self.advance_reference_point
    return unless @current_version_index
    
    group = @versions[@current_version_index]
    spacing = group[:base_spacing] * { "FN" => 1.0, "HN" => 0.5, "QN" => 0.25, "EN" => 0.125, "SN" => 0.0625 }[@current_note]
    vector = case group[:advance_dir]
             when 'X' then [spacing, 0, 0]
             when 'Y' then [0, spacing, 0]
             else [0, 0, spacing]
             end
    group[:reference_point] = Geom::Point3d.new(*group[:reference_point]) + vector
    save_group_to_model(group, group[:id])
    update_panel_display
  end

  def self.set_note_type(key)
    @current_note = { '1' => "FN", '2' => "HN", '3' => "QN", '4' => "EN", '5' => "SN" }[key]
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
    @versions = model.entities.grep(Sketchup::ComponentInstance)
                     .select { |e| e.definition.name.start_with?("GroupData_") }
                     .map { |e| JSON.parse(e.get_attribute("MusicArch", "data"), symbolize_names: true) }
                     .sort_by { |g| g[:id] }
    @current_version_index = @versions.any? ? 0 : nil
  end

  def self.update_panel_display
    return unless @current_version_index
    
    group = @versions[@current_version_index]
    %w[group_id length width height advance_dir rotation_axis spacing].each do |id|
      value = case id
              when "group_id" then "Group #{group[:id]}"
              else group[id.to_sym].to_s
              end
      @dialog.execute_script("document.getElementById('#{id}').value = '#{value}';")
    end
    %w[x y z].each do |axis|
      @dialog.execute_script("document.getElementById('ref_#{axis}').value = '#{group[:reference_point][axis == 'x' ? 0 : axis == 'y' ? 1 : 2]}';")
    end
  end

  def self.get_html_content
    <<~HTML
      <html>
      <body tabindex="0" style="padding:10px;">
        <h2>Music Architecture</h2>
        <div id="group_status">当前组: <span id="group_id">未选择</span></div>
        
        <fieldset>
          <legend>组参数</legend>
          <label>长度 (X): <input type="number" id="length" step="10" value="600"></label><br>
          <label>宽度 (Y): <input type="number" id="width" step="10" value="100"></label><br>
          <label>高度 (Z): <input type="number" id="height" step="10" value="3000"></label><br>
          <label>行进方向: <input type="text" id="advance_dir" value="Y" placeholder="X/Y/Z"></label><br>
          <label>旋转轴: <input type="text" id="rotation_axis" value="Z" placeholder="X/Y/Z"></label><br>
          <label>标准间距: <input type="number" id="spacing" step="10" value="600"></label><br>
          <button onclick="createNewGroup()">创建新组</button>
          <button onclick="updateCurrentGroup()">保存当前组</button>
        </fieldset>

        <fieldset>
          <legend>参考点控制</legend>
          X: <input type="number" id="ref_x">  
          Y: <input type="number" id="ref_y">  
          Z: <input type="number" id="ref_z"><br>
          <button onclick="updateReferencePoint()">更新坐标</button>
          <button onclick="switchGroup('prev')">← 前一组</button>
          <button onclick="switchGroup('next')">后一组 →</button>
        </fieldset>

        <fieldset>
          <legend>音符操作</legend>
          <div>当前音符类型：<span id="current_note">全音符 (FN)</span></div>
          <button onclick="setNoteType('1')">FN</button>
          <button onclick="setNoteType('2')">HN</button>
          <button onclick="setNoteType('3')">QN</button>
          <button onclick="setNoteType('4')">EN</button>
          <button onclick="setNoteType('5')">SN</button>
          <button onclick="advanceReferencePoint()">空拍</button>
        </fieldset>

        <script>
          document.addEventListener('keydown', function(e) {
            const keyMap = { 
              'z':'z','s':'s','x':'x','d':'d','c':'c','v':'v',
              'g':'g','b':'b','h':'h','n':'n','j':'j','m':'m'
            };
            const key = e.key.toLowerCase();
            if (keyMap[key]) {
              sketchup.placeNote(keyMap[key]);
              e.preventDefault();
              e.stopPropagation();
            }
          });

          function createNewGroup() {
            sketchup.createNewGroup(getParams());
          }
          function updateCurrentGroup() {
            sketchup.updateCurrentGroup(getParams());
          }
          function switchGroup(direction) {
            sketchup.switchGroup(direction);
          }
          function updateReferencePoint() {
            const x = document.getElementById('ref_x').value;
            const y = document.getElementById('ref_y').value;
            const z = document.getElementById('ref_z').value;
            sketchup.setReferencePoint(x, y, z);
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
        </script>
      </body>
      </html>
    HTML
  end
end