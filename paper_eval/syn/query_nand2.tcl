set library_file $::env(HBF_ECC_TARGET_LIBRARY)
set_app_var target_library [list $library_file]
set_app_var link_library [concat "*" $target_library]

# Loading the db through list_libs makes its cell attributes queryable without
# elaborating a design.
read_db $library_file
set matches [get_lib_cells -quiet */* -filter {
    name =~ *NAND2* || name =~ *ND2* || name =~ *nd2* || name =~ *nand2*
}]
foreach_in_collection cell $matches {
    puts "CELL [get_object_name $cell] AREA [get_attribute $cell area]"
}
quit
