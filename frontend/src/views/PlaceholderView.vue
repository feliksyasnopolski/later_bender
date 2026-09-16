<script setup>
defineProps({ title: { type: String, required: true }, message: { type: String, required: true } })
</script>

<template>
  <section class="page-intro">
    <p class="eyebrow">Later, Bender</p>
    <h1>{{ title }}</h1>
    <div class="empty-state panel">
      <h2>{{ message }}</h2>
      <p class="muted">This entry point is ready for the next workflow phase.</p>
    </div>
  </section>
</template>
