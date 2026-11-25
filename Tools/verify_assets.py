"""Validate the saved assets in a fresh editor process, without modifying them."""
import unreal

config = unreal.load_asset('/InstantVolumeReducer/IVR_Config')
assert config
default = unreal.get_default_object(config.generated_class())
assert default.get_editor_property('config_id').get_editor_property('mod_reference') == 'InstantVolumeReducer'
section = default.get_editor_property('root_section')
assert section
assert not section.get_editor_property('requires_world_reload'), 'Root section must be editable during gameplay'
prop = section.get_editor_property('section_properties')['ReductionPercent']
assert not prop.get_editor_property('requires_world_reload'), 'Reduction slider must be editable during gameplay'
assert prop.get_editor_property('default_value') == 50
assert prop.get_editor_property('min_value') == 5
assert prop.get_editor_property('max_value') == 95
assert prop.get_editor_property('widget_type') == unreal.CP_IntegerWidgetType.CPI_SLIDER

action = unreal.load_asset('/InstantVolumeReducer/Input/IA_ToggleReducer')
assert action
assert not action.get_editor_property('consume_input')
settings = action.get_editor_property('player_mappable_key_settings')
assert settings.get_editor_property('is_player_mappable')
assert str(settings.get_editor_property('name')) == 'InstantVolumeReducer.Toggle'
context = unreal.load_asset('/InstantVolumeReducer/Input/IMC_InstantVolumeReducer')
assert isinstance(context, unreal.FGInputMappingContext)
assert context.get_editor_property('m_menu_priority') >= 200
mappings = context.get_editor_property('mappings')
assert len(mappings) == 1
assert mappings[0].get_editor_property('action') == action
assert str(mappings[0].get_editor_property('key').get_editor_property('key_name')) == 'F7'
root_bp = unreal.load_asset('/InstantVolumeReducer/RootInstance_InstantVolumeReducer')
assert root_bp
root_data = unreal.EditorAssetLibrary.find_asset_data('/InstantVolumeReducer/RootInstance_InstantVolumeReducer')
assert root_data.get_tag_value('bRootModule') == 'True', 'SML must be able to discover the Blueprint root by its asset tag'
root_module = unreal.get_default_object(root_bp.generated_class())
assert root_module.get_editor_property('root_module')
assert list(root_module.get_editor_property('mod_configurations')) == [config.generated_class()]
assert root_module.get_editor_property('mapping_context') == context
assert root_module.get_editor_property('toggle_action') == action
native_module = unreal.get_default_object(unreal.InstantVolumeReducerGameInstanceModule)
assert not native_module.get_editor_property('root_module'), 'Only the Blueprint child may be the root module'
unreal.log('IVR verification passed: discoverable Blueprint root, direct asset references, config 50% with range 5-95%, rebindable F7')
