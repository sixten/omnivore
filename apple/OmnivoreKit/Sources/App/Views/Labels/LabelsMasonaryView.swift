//
//  LabelsMasonaryView.swift
//
//
//  Created by Jackson Harper on 11/9/22.
//

import Foundation
import SwiftUI

import Models
import Views

struct LabelsMasonaryView: View {
  var onLabelTap: (LinkedItemLabel, TextChip) -> Void

  @State private var totalHeight = CGFloat.zero
  private var labels: [LinkedItemLabel]
  private var selectedLabels: Set<LinkedItemLabel>

  init(
    labels allLabels: [LinkedItemLabel],
    selectedLabels: Set<LinkedItemLabel>,
    onLabelTap: @escaping (LinkedItemLabel, TextChip) -> Void
  ) {
    self.onLabelTap = onLabelTap

    self.labels = allLabels.sortedByName()
    self.selectedLabels = selectedLabels
  }

  var body: some View {
    VStack {
      GeometryReader { geometry in
        self.generateContent(in: geometry)
      }
    }.padding(5)
      .frame(height: totalHeight)
  }

  private func generateContent(in geom: GeometryProxy) -> some View {
    var width = CGFloat.zero
    var height = CGFloat.zero

    return ZStack(alignment: .topLeading) {
      ForEach(labels, id: \.self) { label in
        self.item(for: label, isSelected: self.selectedLabels.contains(label))
          .padding(.horizontal, 5)
          .padding(.vertical, 5)
          .alignmentGuide(.leading, computeValue: { dim in
            if abs(width - dim.width) > geom.size.width {
              width = 0
              height -= dim.height
            }
            let result = width
            if label == self.labels.last {
              width = 0 // last item
            } else {
              width -= dim.width
            }
            return result
          })
          .alignmentGuide(.top, computeValue: { _ in
            let result = height
            if label == self.labels.last {
              height = 0 // last item
            }
            return result
          })
      }
    }
    .background(viewHeightReader($totalHeight))
  }

  private func item(for label: LinkedItemLabel, isSelected: Bool) -> some View {
    TextChip(feedItemLabel: label, negated: false, checked: isSelected, padded: true) { chip in
      onLabelTap(label, chip)
    }
  }

  private func viewHeightReader(_ binding: Binding<CGFloat>) -> some View {
    GeometryReader { geometry -> Color in
      let rect = geometry.frame(in: .local)
      DispatchQueue.main.async {
        binding.wrappedValue = rect.size.height
      }
      return .clear
    }
  }
}
