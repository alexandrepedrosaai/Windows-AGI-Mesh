cmake_minimum_required(VERSION 3.16)

project(WindowsAGIMesh LANGUAGES C)

add_executable(windows_agi_mesh_ci_stub src/main.c)

# Keep this target intentionally minimal so CI can configure/build successfully.
set_target_properties(windows_agi_mesh_ci_stub PROPERTIES
  OUTPUT_NAME "windows-agi-mesh-ci-stub"
)
