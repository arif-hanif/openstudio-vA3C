require 'openstudio'

if /^1\.8/.match(RUBY_VERSION)
  class Struct
    def to_h
      h = {}
      self.class.members.each{|m| h[m.to_sym] = self[m]} 
      return h
    end
  end
end

# Va3c class converts an OpenStudio model to vA3C JSON format for rendering in Three.js
# using export at http://va3c.github.io/projects/#./osm-data-viewer/latest/index.html# as a guide
# many thanks to Theo Armour and the vA3C team for figuring out many of the details here
class VA3C

  Scene = Struct.new(:geometries, :materials, :object)
  
  Geometry = Struct.new(:uuid, :type, :data)
  GeometryData = Struct.new(:vertices, :normals, :uvs, :faces, :scale, :visible, :castShadow, :receiveShadow, :doubleSided)

  Material = Struct.new(:uuid, :type, :color, :ambient, :emissive, :specular, :shininess, :side, :opacity, :transparent, :wireframe)
  
  SceneObject = Struct.new(:uuid, :type, :matrix, :children)
  SceneChild = Struct.new(:uuid, :name, :type, :geometry, :material, :matrix, :userData)
  UserData = Struct.new(:handle, :name, :surfaceType, :constructionName, :spaceName, :thermalZoneName, :spaceTypeName, :buildingStoryName, :outsideBoundaryCondition, :outsideBoundaryConditionObjectName, :sunExposure, :windExposure, :vertices)
  Vertex = Struct.new(:x, :y, :z)
 
  AmbientLight = Struct.new(:uuid, :type, :color, :matrix)
   
  def self.convert_model(model)
    scene = build_scene(model)

    # build up the json hash
    result = Hash.new
    result['metadata'] = { 'version' => 4.3, 'type' => 'Object', 'generator' => 'OpenStudio' }
    result['geometries'] = scene.geometries
    result['materials'] = scene.materials
    result['object'] = scene.object
    
    return result
  end
  
  # format a uuid
  def self.format_uuid(uuid)
    return uuid.to_s.gsub('{','').gsub('}','')
  end
    
  # format color
  def self.format_color(r, g, b)
    return "0x#{r.to_s(16)}#{g.to_s(16)}#{b.to_s(16)}"
  end
  
  # create a material
  def self.make_material(name, color, opacity)

    transparent = false
    if opacity < 1
      transparent = true
    end

    material = {:uuid => "#{format_uuid(OpenStudio::createUUID)}",
                :name => name,
                :type => 'MeshPhongMaterial',
                :color => "#{color}".hex,
                :ambient => "#{color}".hex,
                :emissive => '0x000000'.hex,
                :specular => '0x808080'.hex,
                :shininess => 50,
                :opacity => opacity,
                :transparent => transparent,
                :wireframe => false,
                :side => 2}
    return material
  end

  # create the standard materials
  def self.build_materials(model)
    materials = []
    
    # materials from 'openstudio\openstudiocore\ruby\openstudio\sketchup_plugin\lib\interfaces\MaterialsInterface.rb'
    materials << make_material('Floor', format_color(128, 128, 128), 1) 
    materials << make_material('Floor_Int', format_color(191, 191, 191), 1) 
    
    materials << make_material('Wall', format_color(204, 178, 102), 1) 
    materials << make_material('Wall_Int', format_color(235, 226, 197), 1) 
    
    materials << make_material('Roof', format_color(153, 76, 76), 1) 
    materials << make_material('Roof_Int', format_color(202, 149, 149), 1) 

    materials << make_material('Window', format_color(102, 178, 204), 0.6) 
    materials << make_material('Window_Int', format_color(192, 226, 235), 0.6) 
    
    materials << make_material('Door', format_color(153, 133, 76), 1) 
    materials << make_material('Door_Int', format_color(202, 188, 149), 1) 

    materials << make_material('SiteShading', format_color(75, 124, 149), 1) 
    materials << make_material('SiteShading_Int', format_color(187, 209, 220), 1) 

    materials << make_material('BuildingShading', format_color(113, 76, 153), 1) 
    materials << make_material('BuildingShading_Int', format_color(216, 203, 229), 1) 
    
    materials << make_material('SpaceShading', format_color(76, 110, 178), 1) 
    materials << make_material('SpaceShading_Int', format_color(183, 197, 224), 1) 
    
    materials << make_material('InteriorPartitionSurface', format_color(158, 188, 143), 1) 
    materials << make_material('InteriorPartitionSurface_Int', format_color(213, 226, 207), 1) 
    
    # start textures for boundary conditions
    materials << make_material('Boundary_Surface', format_color(0, 153, 0), 1)
    materials << make_material('Boundary_Adiabatic', format_color(255, 101, 178), 1)
    materials << make_material('Boundary_Space', format_color(255, 0, 0), 1)
    materials << make_material('Boundary_Outdoors', format_color(163, 204, 204), 1)
    materials << make_material('Boundary_Outdoors_Sun', format_color(40, 204, 204), 1)
    materials << make_material('Boundary_Outdoors_Wind', format_color(9, 159, 162), 1)
    materials << make_material('Boundary_Outdoors_SunWind', format_color(68, 119, 161), 1)
    materials << make_material('Boundary_Ground', format_color(204, 183, 122), 1)
    materials << make_material('Boundary_Groundfcfactormethod', format_color(153, 122, 30), 1)
    materials << make_material('Boundary_Groundslabpreprocessoraverage', format_color(255, 191, 0), 1)
    materials << make_material('Boundary_Groundslabpreprocessorcore', format_color(255, 182, 50), 1)
    materials << make_material('Boundary_Groundslabpreprocessorperimeter', format_color(255, 178, 101), 1)
    materials << make_material('Boundary_Groundbasementpreprocessoraveragewall', format_color(204, 51, 0), 1)
    materials << make_material('Boundary_Groundbasementpreprocessoraveragefloor', format_color(204, 81, 40), 1)
    materials << make_material('Boundary_Groundbasementpreprocessorupperwall', format_color(204, 112, 81), 1)
    materials << make_material('Boundary_Groundbasementpreprocessorlowerwall', format_color(204, 173, 163), 1)
    materials << make_material('Boundary_Othersidecoefficients', format_color(63, 63, 63), 1)
    materials << make_material('Boundary_Othersideconditionsmodel', format_color(153, 0, 76), 1) 
    
    # make construction materials
    model.getConstructionBases.each do |construction|
      color = construction.renderingColor
      if color.empty?
        color = OpenStudio::Model::RenderingColor.new(model)
        construction.setRenderingColor(color)
      else
        color = color.get
      end
      name = "Construction_#{construction.name.to_s}"
      make_material(name, format_color(color.renderingRedValue, color.renderingGreenValue, color.renderingBlueValue), color.renderingAlphaValue / 255.to_f)
    end
    
    # make thermal zone materials
    model.getThermalZones.each do |zone|
      color = zone.renderingColor
      if color.empty?
        color = OpenStudio::Model::RenderingColor.new(model)
        zone.setRenderingColor(color)
      else
        color = color.get        
      end
      name = "ThermalZone_#{zone.name.to_s}"
      make_material(name, format_color(color.renderingRedValue, color.renderingGreenValue, color.renderingBlueValue), color.renderingAlphaValue / 255.to_f)
    end
    
    # make space type materials
    model.getSpaceTypes.each do |spaceType|
      color = spaceType.renderingColor
      if color.empty?
        color = OpenStudio::Model::RenderingColor.new(model)
        spaceType.setRenderingColor(color)
      else
        color = color.get        
      end
      name = "SpaceType_#{spaceType.name.to_s}"
      make_material(name, format_color(color.renderingRedValue, color.renderingGreenValue, color.renderingBlueValue), color.renderingAlphaValue / 255.to_f)
    end
    
    # make building story materials
    model.getBuildingStorys.each do |buildingStory|
      color = buildingStory.renderingColor
      if color.empty?
        color = OpenStudio::Model::RenderingColor.new(model)
        buildingStory.setRenderingColor(color)
      else
        color = color.get        
      end
      name = "BuildingStory_#{buildingStory.name.to_s}"
      make_material(name, format_color(color.renderingRedValue, color.renderingGreenValue, color.renderingBlueValue), color.renderingAlphaValue / 255.to_f)
    end
    
    return materials
  end

  # get the index of a vertex out of a list
  def self.get_vertex_index(vertex, vertices, tol = 0.001)
    vertices.each_index do |i|
      if OpenStudio::getDistance(vertex, vertices[i]) < tol
        return i
      end
    end
    vertices << vertex
    return (vertices.length - 1)
  end

  # flatten array of vertices into a single array
  def self.flatten_vertices(vertices)
    result = []
    vertices.each do |vertex|
      #result << vertex.x
      #result << vertex.y
      #result << vertex.z
      
      result << vertex.x
      result << vertex.z
      result << -vertex.y
    end
    return result
  end

  # turn a surface into geometries, the first one is the surface, remaining are sub surfaces
  def self.make_geometries(surface)
    geometries = []
    user_datas = []

    # get the transformation to site coordinates
    site_transformation = OpenStudio::Transformation.new
    planar_surface_group = surface.planarSurfaceGroup
    if not planar_surface_group.empty?
      site_transformation = planar_surface_group.get.siteTransformation
    end

    # get the vertices
    surface_vertices = surface.vertices
    t = OpenStudio::Transformation::alignFace(surface_vertices)
    r = t.rotationMatrix
    tInv = t.inverse
    surface_vertices = OpenStudio::reverse(tInv*surface_vertices)

    # get vertices of all sub surfaces
    sub_surface_vertices = OpenStudio::Point3dVectorVector.new
    sub_surfaces = surface.subSurfaces
    sub_surfaces.each do |sub_surface|
      sub_surface_vertices << OpenStudio::reverse(tInv*sub_surface.vertices)
    end

    # triangulate surface
    triangles = OpenStudio::computeTriangulation(surface_vertices, sub_surface_vertices)
    if triangles.empty?
      puts "Failed to triangulate surface #{surface.name} with #{sub_surfaces.size} sub surfaces"
      return geometries
    end

    all_vertices = []
    face_indices = []
    triangles.each do |vertices|
      vertices = site_transformation*t*vertices
      #normal = site_transformation.rotationMatrix*r*z

      # https://github.com/mrdoob/three.js/wiki/JSON-Model-format-3
      # 0 indicates triangle
      # 16 indicates triangle with normals
      face_indices << 0
      vertices.each do |vertex|
        face_indices << get_vertex_index(vertex, all_vertices)  
      end

      # convert to 1 based indices
      #face_indices.each_index {|i| face_indices[i] = face_indices[i] + 1}
    end

    data = GeometryData.new
    data.vertices = flatten_vertices(all_vertices)
    data.normals = [] 
    data.uvs = []
    data.faces = face_indices
    data.scale = 1
    data.visible = true
    data.castShadow = true
    data.receiveShadow = false
    data.doubleSided = true
    
    geometry = Geometry.new
    geometry.uuid = format_uuid(surface.handle)
    geometry.type = 'Geometry'
    geometry.data = data.to_h
    geometries << geometry.to_h
    
    surface_user_data = UserData.new
    surface_user_data.handle = format_uuid(surface.handle)
    surface_user_data.name = surface.name.to_s
    surface_user_data.surfaceType = surface.surfaceType
    
    surface_user_data.outsideBoundaryCondition = surface.outsideBoundaryCondition
    adjacent_surface = surface.adjacentSurface
    if adjacent_surface.is_initialized
      surface_user_data.outsideBoundaryConditionObjectName = adjacent_surface.get.name.to_s
    end
    surface_user_data.sunExposure = surface.sunExposure
    surface_user_data.windExposure = surface.windExposure
    
    construction = surface.construction
    if construction.is_initialized
      surface_user_data.constructionName = construction.get.name.to_s
    end
    
    space = surface.space
    if space.is_initialized
      space = space.get
      surface_user_data.spaceName = space.name.to_s
      
      thermal_zone = space.thermalZone
      if thermal_zone.is_initialized
        surface_user_data.thermalZoneName = thermal_zone.get.name.to_s
      end
      
      space_type = space.spaceType
      if space_type.is_initialized
        surface_user_data.spaceTypeName = space_type.get.name.to_s
      end
      
      building_story = space.buildingStory
      if building_story.is_initialized
        surface_user_data.buildingStoryName = building_story.get.name.to_s
      end
    end
    
    vertices = []
    surface.vertices.each do |v| 
      vertex = Vertex.new
      vertex.x = v.x
      vertex.y = v.y
      vertex.z = v.z
      vertices << vertex.to_h
    end
    surface_user_data.vertices = vertices
    user_datas << surface_user_data.to_h
    
    # now add geometry for each sub surface
    sub_surfaces.each do |sub_surface|
   
      # triangulate sub surface
      sub_surface_vertices = OpenStudio::reverse(tInv*sub_surface.vertices)
      triangles = OpenStudio::computeTriangulation(sub_surface_vertices, OpenStudio::Point3dVectorVector.new)
      
      all_vertices = []
      face_indices = []
      triangles.each do |vertices|
        vertices = site_transformation*t*vertices
        #normal = site_transformation.rotationMatrix*r*z
        
        # https://github.com/mrdoob/three.js/wiki/JSON-Model-format-3
        # 0 indicates triangle
        # 16 indicates triangle with normals
        face_indices << 0
        vertices.each do |vertex|
          face_indices << get_vertex_index(vertex, all_vertices)  
        end    

        # convert to 1 based indices
        #face_indices.each_index {|i| face_indices[i] = face_indices[i] + 1}
      end
      
      data = GeometryData.new
      data.vertices = flatten_vertices(all_vertices)
      data.normals = [] 
      data.uvs = []
      data.faces = face_indices
      data.scale = 1
      data.visible = true
      data.castShadow = true
      data.receiveShadow = false
      data.doubleSided = true
      
      geometry = Geometry.new
      geometry.uuid = format_uuid(sub_surface.handle)
      geometry.type = 'Geometry'
      geometry.data = data.to_h
      geometries << geometry.to_h
      
      sub_surface_user_data = UserData.new
      sub_surface_user_data.handle = format_uuid(sub_surface.handle)
      sub_surface_user_data.name = sub_surface.name.to_s
      sub_surface_user_data.surfaceType = sub_surface.subSurfaceType
      
      sub_surface_user_data.outsideBoundaryCondition = surface_user_data.outsideBoundaryCondition
      adjacent_sub_surface = sub_surface.adjacentSubSurface
      if adjacent_sub_surface.is_initialized
        sub_surface_user_data.outsideBoundaryConditionObjectName = adjacent_sub_surface.get.name.to_s
      end
      sub_surface_user_data.sunExposure = surface_user_data.sunExposure
      sub_surface_user_data.windExposure = surface_user_data.windExposure
      
      construction = sub_surface.construction
      if construction.is_initialized
        sub_surface_user_data.constructionName = construction.get.name.to_s
      end     
      sub_surface_user_data.spaceName = surface_user_data.spaceName
      sub_surface_user_data.thermalZoneName = surface_user_data.thermalZoneName
      sub_surface_user_data.spaceTypeName = surface_user_data.spaceTypeName
      sub_surface_user_data.buildingStoryName = surface_user_data.buildingStoryName

      vertices = []
      surface.vertices.each do |v| 
        vertex = Vertex.new
        vertex.x = v.x
        vertex.y = v.y
        vertex.z = v.z
        vertices << vertex.to_h
      end
      sub_surface_user_data.vertices = vertices
      user_datas << sub_surface_user_data.to_h     
    end

    return [geometries, user_datas]
  end
  
  # turn a shading surface into geometries
  def self.make_shade_geometries(surface)
    geometries = []
    user_datas = []

    # get the transformation to site coordinates
    site_transformation = OpenStudio::Transformation.new
    planar_surface_group = surface.planarSurfaceGroup
    if not planar_surface_group.empty?
      site_transformation = planar_surface_group.get.siteTransformation
    end
    shading_surface_group = surface.shadingSurfaceGroup
    shading_surface_type = 'Building'
    space_name = nil
    thermal_zone_name = nil
    space_type_name = nil
    building_story_name = nil
    if not shading_surface_group.empty?
      shading_surface_type = shading_surface_group.get.shadingSurfaceType
      
      space = shading_surface_group.get.space
      if space.is_initialized
        space = space.get
        space_name = space.name.to_s
        
        thermal_zone = space.thermalZone
        if thermal_zone.is_initialized
          thermal_zone_name = thermal_zone.get.name.to_s
        end
        
        space_type = space.spaceType
        if space_type.is_initialized
          space_type_name = space_type.get.name.to_s
        end
        
        building_story = space.buildingStory
        if building_story.is_initialized
          building_story_name = building_story.get.name.to_s
        end
      end
    end
    
    # get the vertices
    surface_vertices = surface.vertices
    t = OpenStudio::Transformation::alignFace(surface_vertices)
    r = t.rotationMatrix
    tInv = t.inverse
    surface_vertices = OpenStudio::reverse(tInv*surface_vertices)

    # triangulate surface
    triangles = OpenStudio::computeTriangulation(surface_vertices, OpenStudio::Point3dVectorVector.new)
    if triangles.empty?
      puts "Failed to triangulate shading surface #{surface.name}"
      return geometries
    end

    all_vertices = []
    face_indices = []
    triangles.each do |vertices|
      vertices = site_transformation*t*vertices
      #normal = site_transformation.rotationMatrix*r*z

      # https://github.com/mrdoob/three.js/wiki/JSON-Model-format-3
      # 0 indicates triangle
      # 16 indicates triangle with normals
      face_indices << 0
      vertices.each do |vertex|
        face_indices << get_vertex_index(vertex, all_vertices)  
      end

      # convert to 1 based indices
      #face_indices.each_index {|i| face_indices[i] = face_indices[i] + 1}
    end

    data = GeometryData.new
    data.vertices = flatten_vertices(all_vertices)
    data.normals = [] 
    data.uvs = []
    data.faces = face_indices
    data.scale = 1
    data.visible = true
    data.castShadow = true
    data.receiveShadow = false
    data.doubleSided = true
    
    geometry = Geometry.new
    geometry.uuid = format_uuid(surface.handle)
    geometry.type = 'Geometry'
    geometry.data = data.to_h
    geometries << geometry.to_h
    
    surface_user_data = UserData.new
    surface_user_data.handle = format_uuid(surface.handle)
    surface_user_data.name = surface.name.to_s
    surface_user_data.surfaceType = shading_surface_type + 'Shading'
  
    surface_user_data.outsideBoundaryCondition = nil
    surface_user_data.outsideBoundaryConditionObjectName = nil
    surface_user_data.sunExposure = 'SunExposed'
    surface_user_data.windExposure = 'WindExposed'
    
    construction = surface.construction
    if construction.is_initialized
      surface_user_data.constructionName = construction.get.name.to_s
    end
    
    surface_user_data.spaceName = space_name
    surface_user_data.thermalZoneName = thermal_zone_name
    surface_user_data.spaceTypeName = space_type_name
    surface_user_data.buildingStoryName = building_story_name

    vertices = []
    surface.vertices.each do |v| 
      vertex = Vertex.new
      vertex.x = v.x
      vertex.y = v.y
      vertex.z = v.z
      vertices << vertex.to_h
    end
    surface_user_data.vertices = vertices
    user_datas << surface_user_data.to_h

    return [geometries, user_datas]
  end  

  def self.identity_matrix
    return [1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1]
  end

  def self.build_scene(model)

    materials = build_materials(model)
    
    object = Hash.new
    object[:uuid] = format_uuid(OpenStudio::createUUID)
    object[:type] = 'Scene'
    object[:matrix] = identity_matrix
    object[:children] = []
    
    floor_material = materials.find {|m| m[:name] == 'Floor'}
    wall_material = materials.find {|m| m[:name] == 'Wall'}
    roof_material = materials.find {|m| m[:name] == 'Roof'}
    window_material = materials.find {|m| m[:name] == 'Window'}
    door_material = materials.find {|m| m[:name] == 'Door'}
    site_shading_material = materials.find {|m| m[:name] == 'SiteShading'}
    building_shading_material = materials.find {|m| m[:name] == 'BuildingShading'}
    space_shading_material = materials.find {|m| m[:name] == 'SpaceShading'}
    interior_partition_surface_material = materials.find {|m| m[:name] == 'InteriorPartitionSurface'}
    
    # loop over all surfaces
    all_geometries = []
    model.getSurfaces.each do |surface|

      material = nil
      surfaceType = surface.surfaceType.upcase
      if surfaceType == 'FLOOR'
        material = floor_material
      elsif surfaceType == 'WALL'
        material = wall_material
      elsif surfaceType == 'ROOFCEILING'
        material = roof_material  
      end
  
      geometries, user_datas = make_geometries(surface)
      geometries.each_index do |i| 
        geometry = geometries[i]
        user_data = user_datas[i]
        
        all_geometries << geometry

        scene_child = SceneChild.new
        scene_child.uuid = format_uuid(OpenStudio::createUUID) 
        scene_child.name = "#{surface.name.to_s} #{i}"
        scene_child.type = "Mesh"
        scene_child.geometry = geometry[:uuid]
        
        if i == 0
          # first geometry is base surface
          scene_child.material = material[:uuid]
        else
          # sub surface
          if /Window/.match(user_data[:surfaceType]) || /Glass/.match(user_data[:surfaceType]) 
            scene_child.material =  window_material[:uuid]
          else
            scene_child.material =  door_material[:uuid]
          end
        end
        
        scene_child.matrix = identity_matrix
        scene_child.userData = user_data
        object[:children] << scene_child.to_h
      end
      
    end
    
    # loop over all shading surfaces
    model.getShadingSurfaces.each do |surface|
  
      geometries, user_datas = make_shade_geometries(surface)
      geometries.each_index do |i| 
        geometry = geometries[i]
        user_data = user_datas[i]
        
        material = nil
        if /Site/.match(user_data[:surfaceType])
          material = site_shading_material
        elsif /Building/.match(user_data[:surfaceType]) 
          material = building_shading_material
        elsif /Space/.match(user_data[:surfaceType]) 
          material = space_shading_material
        end
        
        all_geometries << geometry

        scene_child = SceneChild.new
        scene_child.uuid = format_uuid(OpenStudio::createUUID) 
        scene_child.name = "#{surface.name.to_s} #{i}"
        scene_child.type = 'Mesh'
        scene_child.geometry = geometry[:uuid]
        scene_child.material = material[:uuid]
        scene_child.matrix = identity_matrix
        scene_child.userData = user_data
        object[:children] << scene_child.to_h
      end
      
    end    
    
    #light = AmbientLight.new
    #light.uuid = "#{format_uuid(OpenStudio::createUUID)}"
    #light.type = "AmbientLight"
    #light.color = "0xFFFFFF".hex
    #light.matrix = identity_matrix
    #object[:children] << light.to_h
      
    scene = Scene.new
    scene.geometries = all_geometries
    scene.materials = materials
    scene.object = object

    return scene
  end
  
  
end