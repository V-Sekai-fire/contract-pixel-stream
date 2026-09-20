cmake_minimum_required(VERSION 3.16)
project(pixel_stream_proof LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_executable(vector_replay proof/vector_replay.cpp)
target_include_directories(vector_replay PRIVATE include)

enable_testing()
add_test(NAME vectors
  COMMAND vector_replay ${CMAKE_CURRENT_SOURCE_DIR}/vectors/corpus.txt)
