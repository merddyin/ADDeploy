# Note

These are extra functions used in the build script. They are purposefully scoped to the script level so as to be useable outside of the task level they are dot sourced within (the global scope would leave them in the session after build script is called so we cannot use that).