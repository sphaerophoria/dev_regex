"use strict";

const color_pallate = ["#dd3838", "#38cc38", "#3838cc", "#cccc38", "#38cccc"];

function makeInputTextSpans(input_text) {
  const spans = [];
  for (const c of input_text) {
    const span = document.createElement("span");
    span.innerText = c;
    spans.push(span);
  }

  // One for EOL
  const span = document.createElement("span");
  spans.push(span);

  return spans;
}

function makeColors(matchers) {
  const ret = [];
  for (let i = 0; i < matchers.length; ++i) {
    ret.push(color_pallate[i % color_pallate.length]);
  }
  return ret;
}

function setSpanColors(spans, matcher_state, colors) {
  for (let i = 0; i < matcher_state.length; ++i) {
    const bounds = matcher_state[i];
    const state_spans = spans.slice(bounds[0], bounds[1]);
    for (const span of state_spans) {
      span.style.backgroundColor = colors[i];
    }
  }
}

function addCursor(spans, cursor_pos) {
  const adjusted_pos = Math.min(cursor_pos, spans.length - 1);
  const span = spans[adjusted_pos];
  span.classList.add("string-pos");
  const cursor = document.createElement("div");
  cursor.innerText = "^";
  span.appendChild(cursor);
}

function putSpansInInput(spans) {
  const input_div = document.getElementById("input");
  input_div.innerHTML = "";
  for (const span of spans) {
    input_div.appendChild(span);
  }
}

function renderMatchers(matchers, colors) {
  const parent_div = document.getElementById("regex");
  parent_div.innerHTML = "";

  for (let i = 0; i < matchers.length; ++i) {
    const div = document.createElement("div");
    div.innerText = matchers[i];
    div.style.backgroundColor = colors[i];
    div.style.width = "fit-content";
    div.style.minHeight = "1em";
    div.style.minWidth = "1ch";
    parent_div.appendChild(div);
  }
}

function render(recording, i) {
  const matchers = recording.matchers;
  const colors = makeColors(matchers);
  renderMatchers(matchers, colors);

  const spans = makeInputTextSpans(recording.input_string);
  const matcher_state = recording.items[i].matcher_state;
  const cursor_pos = recording.items[i].string_pos;

  setSpanColors(spans, matcher_state, colors);
  addCursor(spans, cursor_pos);
  putSpansInInput(spans);
}

async function init() {
  const recording_response = await fetch("recording.json");
  const recording = await recording_response.json();

  const replay_state = document.getElementById("replay_state");
  replay_state.max = recording.items.length - 1;
  render(recording, recording.items.length - 1);
  replay_state.oninput = (ev) => {
    render(recording, ev.target.value);
  };
}

window.onload = init;
