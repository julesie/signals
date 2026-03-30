import { Controller } from "@hotwired/stimulus"
import { Chart } from "chart.js/auto"

export default class extends Controller {
  static targets = ["canvas"]
  static values = { data: Array, label: String }

  connect() {
    this.chart = new Chart(this.canvasTarget, {
      type: "line",
      data: {
        labels: this.dataValue.map(d => d.date),
        datasets: [{
          label: this.labelValue,
          data: this.dataValue.map(d => d.value),
          borderColor: "rgb(99, 102, 241)",
          backgroundColor: "rgba(99, 102, 241, 0.1)",
          fill: true,
          tension: 0.3,
          pointRadius: 3,
          pointHoverRadius: 6
        }]
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        plugins: {
          tooltip: {
            callbacks: {
              title: (items) => items[0].label
            }
          }
        },
        scales: {
          x: {
            ticks: { color: "rgb(161, 161, 170)" },
            grid: { color: "rgba(161, 161, 170, 0.1)" }
          },
          y: {
            ticks: { color: "rgb(161, 161, 170)" },
            grid: { color: "rgba(161, 161, 170, 0.1)" }
          }
        }
      }
    })
  }

  disconnect() {
    if (this.chart) {
      this.chart.destroy()
    }
  }
}
