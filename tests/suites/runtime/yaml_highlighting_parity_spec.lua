return {
    id = "runtime.yaml_highlighting_parity",
    description = "Checks the YAML constructs in test.yml against Neovim syntax groups.",

    run = function(ctx)
        local backend = ctx.backend
        local Assert = ctx.assert
        local path = Assert.temp_path(backend, "yaml-highlighting-parity", ".yml")
        Assert.write_file(backend, path, [[---
# This playbook is designed to push configuration files to a remote host for
# customization of a user account.
# The plan is to expand this playbook to also create the account with approiate
# group membership.
# To make the playbook more portable, variables are used. Before running the playbook,
# be sure to create and customize the vars/newuser.yml variables file.

- name: deploy configuration for new user
  hosts: newhosts
  vars_files:
    - vars/newuser.yml
  tasks:
    - name: Set authorized keys taken from url
      authorized_key:
        user: "{{ newuser }}"
        state: present
        key: "{{ key_url }}"
]])

        local groups = Assert.eval_block(backend, "YAML highlight parity", string.format([[
            vim.cmd("filetype on")
            vim.cmd("syntax on")
            vim.cmd("edit " .. vim.fn.fnameescape(%q))

            return {
                vim.fn.synIDattr(vim.fn.synID(1, 1, 0), "name"),
                vim.fn.synIDattr(vim.fn.synID(2, 1, 0), "name"),
                vim.fn.synIDattr(vim.fn.synID(9, 1, 0), "name"),
                vim.fn.synIDattr(vim.fn.synID(9, 3, 0), "name"),
                vim.fn.synIDattr(vim.fn.synID(9, 7, 0), "name"),
                vim.fn.synIDattr(vim.fn.synID(9, 9, 0), "name"),
                vim.fn.synIDattr(vim.fn.synID(10, 3, 0), "name"),
                vim.fn.synIDattr(vim.fn.synID(12, 7, 0), "name"),
                vim.fn.synIDattr(vim.fn.synID(14, 7, 0), "name"),
                vim.fn.synIDattr(vim.fn.synID(16, 9, 0), "name"),
                vim.fn.synIDattr(vim.fn.synID(16, 13, 0), "name"),
                vim.fn.synIDattr(vim.fn.synID(16, 15, 0), "name"),
                vim.fn.synIDattr(vim.fn.synID(16, 16, 0), "name"),
                vim.fn.synIDattr(vim.fn.synID(16, 29, 0), "name"),
            }
        ]], path))

        Assert.table_eq("YAML highlights match Neovim", groups, {
            "yamlDocumentStart",
            "yamlComment",
            "yamlBlockCollectionItemStart",
            "yamlBlockMappingKey",
            "yamlBlockMappingDelimiter",
            "yamlPlainScalar",
            "yamlBlockMappingKey",
            "yamlPlainScalar",
            "yamlBlockMappingKey",
            "yamlBlockMappingKey",
            "yamlBlockMappingDelimiter",
            "yamlFlowStringDelimiter",
            "yamlFlowString",
            "yamlFlowStringDelimiter",
        })
    end,
}
