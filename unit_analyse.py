import argparse
import re
from pprint import pprint
import pandas as pd
import os
import subprocess
import lupa
from pdb import set_trace
from pathlib import Path


def parser_add_dynamic_args(_parser):
    parsed, unknown = _parser.parse_known_args()

    for arg in unknown:
        default_value = None
        if arg.startswith(('-', '--')):
            split_pattern = '[= ]'
            flag_pattern = r'^\s?-+\w+$'
            kw_args = {}
            if re.search(split_pattern, arg):
                key, value = re.split(split_pattern, arg, 1)
            elif re.match(flag_pattern, arg):
                key = arg
                value = True
                kw_args['default'] = True
                kw_args['action'] = 'store_true'
            else:
                set_trace()
                raise Exception('arg')

            kw_args['dest'] = key.replace('-', '')

            if isinstance(value, bool):
                pass
            elif value.lower() == 'false' or value.lower() == 'true':
                # value = eval(value.capitalize())
                kw_args['type'] = bool
            elif value.isdigit():
                kw_args['type'] = int
            elif value.isdecimal() or (hasattr(value, 'isascii') and not value.isascii() and value.isnumerical()):
                kw_args['type'] = float
            else:
                kw_args['type'] = str
            # print(f'default_value {default_value}')
            # _parser.add_argument(key, dest=key.replace('-', ''), type=value_type, **kw_args)
            print(kw_args)
            _parser.add_argument(key, **kw_args)

    return _parser


display = pd.options.display

display.max_columns = 10000
display.max_rows = 10000
display.max_colwidth = 199
display.width = None

ta_path = r'C:\Users\a\Documents\TA'

result = subprocess.run(['git', 'pull'], stdout=subprocess.PIPE, cwd=ta_path)
print(f'git repo: {result.stdout.decode()}')

lua = lupa.LuaRuntime(unpack_returned_tuples=True)

buildcostmetal = 'buildcostmetal'
buildcostenergy = 'buildcostenergy'
df_dps = 'dps'
cost = 'cost'
dps_cost = 'dps per cost'
health_cost = 'health_cost'

constructors = {}
id_name = {}
name_id = {}

parser = argparse.ArgumentParser()
parser = parser_add_dynamic_args(parser)
parser.add_argument('mode', type=str, nargs='?', help='Mode select', default='')
# parser.add_argument('--health', type=str, nargs='?', help='Filter results to item name', default='')
# parser.add_argument('--ra', type=str, nargs='?', help='Filter results to item name', default='')
# parser.add_argument('--gaw', type=bool, nargs='?', help='web diff', )  # default=False)

cmdline_args = parser.parse_args()


def get_units_dict():
    units_dir = os.path.join(ta_path, 'units')
    unit_dicts_ = []

    for file in os.listdir(units_dir):

        filename = os.fsdecode(file)
        if not filename.endswith(".lua"):
            continue

        file_path = os.path.join(units_dir, filename)
        contents = Path(file_path).read_text()
        contents = contents.replace('return ', '')
        lua_eval = lua.eval(contents)
        key = list(lua_eval.keys())[0]
        unit_def = lua_eval[key]

        unit_dict = {}

        for def_key, def_value in unit_def.items():
            if isinstance(def_value, (list, map, dict, tuple)):
                set_trace()
            unit_dict[def_key] = def_value
        unit_dict['key'] = key
        unit_dict['faction'] = unit_def['customparams']['faction']

        id_name[key] = unit_def['name']
        name_id[unit_def['name']] = key

        if 'weapondefs' in unit_def:

            dps = 0
            for weapon_def_name in unit_def['weapondefs']:
                weapon_def = unit_def['weapondefs'][weapon_def_name]

                default_damage = weapon_def['damage']['default']
                reload_time = weapon_def['reloadtime']

                try:
                    dps += default_damage // (reload_time or 1)
                except Exception:
                    set_trace()
                # print(f'{weapon_def_name} {default_damage}/{reload_time} = {dps} dps')

            unit_dict[df_dps] = dps

        elif 'buildoptions' in unit_def:
            constructors[key] = set(unit_def['buildoptions'].values())

        unit_dicts_.append(unit_dict)
    return unit_dicts_


def set_constructed(row):
    constructed = []
    for constructor_key, buildoptions in constructors.items():
        if row.name in buildoptions:
            constructed.append(id_name[constructor_key])
    # row['constructed'] = constructed
    return constructed


df = pd.DataFrame(get_units_dict())
df = df.set_index('key')

df[cost] = df[buildcostmetal] + df[buildcostenergy] // 8

df['constructed'] = df.apply(set_constructed, axis=1)
df[dps_cost] = df[df_dps] / df[cost]
df[health_cost] = df['maxdamage'] / df[cost]

if cmdline_args.mode == 'health':
    df = df.sort_values(health_cost, ascending=False)
else:
    df = df.sort_values(dps_cost, ascending=False)

# with pd.option_context('display.max_rows', None, 'display.max_columns', None, 'display.max_colwidth', -1):  # more options can be specified also
#     print(df)
# df = df[df['name'].str.contains('Commander') == False]
df = df[df['commander'] != True]
print_df = df.drop([buildcostmetal, buildcostenergy], axis=1)

pprint(list(df.columns))

tank_filter = (print_df['maxvelocity'] > 0)

dps_filter = print_df['maxvelocity'] > 0

if cmdline_args.mode == 'health':
    print_df = print_df[tank_filter]
else:
    print_df = print_df[dps_filter]

# set_trace()

for arg, value in vars(cmdline_args).items():
    if arg == 'mode':
        continue
    print(f'filtering {arg}={value}')
    if isinstance(value, str):
        if '>' in value:
            # print(float(value.replace('>', '')))
            print_df = print_df[print_df[arg] >= int(value.replace('>', ''))]
        elif '<' in value:
            print_df = print_df[print_df[arg] <= int(value.replace('<', ''))]
    else:
        print_df = print_df[print_df[arg] == value]

display_cols = [
    'faction',
    'name',
    'maxdamage',
    'maxvelocity',
    'dps',
    'cost',
    'constructed',
    health_cost,
    'dps per cost',
    'canfly',
    'workertime',
]
print(print_df[display_cols].head(100).to_string(index=True))
# pprint(constructors)
