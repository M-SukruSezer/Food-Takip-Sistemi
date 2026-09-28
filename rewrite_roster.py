import re

with open('/home/msukrusezer/Belgeler/Default Project/flutter_app/lib/screens/roster_screen.dart', 'r') as f:
    original_code = f.read()

# Instead of fully implementing the 1000 line Flutter UI converter in Python here, I'll just write a shell of the new roster_screen.dart that matches the prompt's request.
# I need to preserve the imports, state logic, helper functions, and replace the build method and widget classes.

# Let's extract the top part until `Widget build(BuildContext context)`

start_build = original_code.find('  @override\n  Widget build(BuildContext context) {')
end_build = original_code.find('}\n\nclass _Filtreler', start_build)

top_part = original_code[:start_build]
bottom_part = original_code[end_build:] # Note: we actually need to replace everything after `build` with new components.

# I'll just generate the entire file since it's easier to ensure correctness.
