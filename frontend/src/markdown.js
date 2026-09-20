import { marked } from 'marked'
import DOMPurify from 'dompurify'

marked.setOptions({ breaks: true, gfm: true })

export function renderMarkdown(value) {
  return DOMPurify.sanitize(marked.parse(value || ''))
}
