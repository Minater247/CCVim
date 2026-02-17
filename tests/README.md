# Testing Library
The files in this directory pertain to testing the CCVim environmnt and functionalities.

Note that these tests *are going to be rewritten at some point soon*. The current test suite is not very well managed and is littered with AI-generated files from when I was testing it out.

- The `test_mocks.lua` file provides MockEnv, used to stub the ComputerCraft environment enough to run tests.
- The `regex_bench/` directory contains older, but likely still valid test cases. Some newer tests were AI generated as I was testing Codex' code review capabilities in some more recent development, so do not treat them as a gold standard.
- The `in_editor/` directory contains tests which test the editor's functionality from within the editor itself. This allows for the instantiation of a full CraftOS environment, but requires manual runs of the test cases from within the emulator.