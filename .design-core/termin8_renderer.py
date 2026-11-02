import re

def rust_rgb(value):
    return '[' + ', '.join(f'0x{part:02x}' for part in value) + ']'

def rust_number(value):
    return repr(float(value))

def rust_name(value):
    return re.sub(r'(?<!^)(?=[A-Z])', '_', value).upper()

def render_termin8(core):
    profile = core['profiles']['termin8']
    lines = ['use crate::theme::Theme;', '']
    names = profile['paletteOrder']
    lines.append('pub const THEME_NAMES: [&str; ' + str(len(names)) + '] = [' + ', '.join('"' + name + '"' for name in names) + '];')
    for role, color in profile['fallback'].items():
        lines.append('pub const FALLBACK_' + rust_name(role) + ': [u8; 3] = ' + rust_rgb(color) + ';')
    for key, value in profile['chrome'].items():
        lines.append('pub const CHROME_' + rust_name(key) + ': f32 = ' + rust_number(value) + ';')
    for key, value in profile['hostedPanel'].items():
        lines.append('pub const HOSTED_' + rust_name(key) + ': f32 = ' + rust_number(value) + ';')
    for name in names:
        palette = profile['palettes'][name]
        lines.extend(['', 'pub const ' + name.upper() + ': Theme = Theme {', '    name: "' + name + '",'])
        for field in ['bg', 'fg', 'cursor', 'selection_bg']:
            lines.append('    ' + field + ': ' + rust_rgb(palette[field]) + ',')
        lines.append('    accent: Some(' + rust_rgb(palette['accent']) + '),')
        lines.append('    ansi: [')
        lines.extend('        ' + rust_rgb(color) + ',' for color in palette['ansi'])
        lines.extend(['    ],', '};'])
    metrics = []
    for name, value in profile['panelMetrics'].items():
        rendered = value['alias'] if isinstance(value, dict) else rust_number(value)
        metrics.append('pub const ' + name + ': f32 = ' + rendered + ';')
    return {
        '.design-core/generated/termin8-theme.rs': '\n'.join(lines) + '\n',
        '.design-core/generated/termin8-panel-metrics.rs': '\n'.join(metrics) + '\n',
    }
