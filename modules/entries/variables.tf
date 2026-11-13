# SPDX-License-Identifier: BSD-2-Clause
# SPDX-FileCopyrightText: 2026 Aryan Ameri <github@aryan.ameri.coffee>

variable "repositories" {
  description = "local.repositories as written, by slug: every entry with every key it sets."
  # Not an object type: conversion to one would drop the very keys this
  # module is here to find.
  type     = any
  nullable = false
}
