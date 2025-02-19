import Models
import SwiftUI
import Views

struct HighlightsListCard: View {
  @State var isContextMenuOpen = false
  @State var annotation = String()
  @State var showAnnotationModal = false

  let highlightParams: HighlightListItemParams
  @Binding var hasHighlightMutations: Bool
  let onSaveAnnotation: (String) -> Void
  let onDeleteHighlight: () -> Void
  let onSetLabels: (String) -> Void

  @State var errorAlertMessage: String?
  @State var showErrorAlertMessage = false

  var contextMenuView: some View {
    Group {
      Button(
        action: {
          #if os(iOS)
            UIPasteboard.general.string = highlightParams.quote
          #endif

          #if os(macOS)
            let pasteBoard = NSPasteboard.general
            pasteBoard.clearContents()
            pasteBoard.writeObjects([highlightParams.quote as NSString])
          #endif

          Snackbar.show(message: "Highlight copied")
        },
        label: { Label("Copy", systemImage: "doc.on.doc") }
      )
      Button(
        action: {
          onSetLabels(highlightParams.highlightID)
        },
        label: { Label(LocalText.labelsGeneric, systemImage: "tag") }
      )
      Button(
        action: onDeleteHighlight,
        label: { Label("Delete", systemImage: "trash") }
      )
    }
  }

  var noteSection: some View {
    HStack {
      let isEmpty = highlightParams.annotation.isEmpty
      Spacer(minLength: 6)

      Text(isEmpty ? "Add Notes..." : highlightParams.annotation)
        .lineSpacing(6)
        .accentColor(.appGraySolid)
        .foregroundColor(isEmpty ? .appGrayText : .appGrayTextContrast)
        .font(.appSubheadline)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.appButtonBackground)
        .cornerRadius(8)
    }
    .onTapGesture {
      annotation = highlightParams.annotation
      showAnnotationModal = true
    }
  }

  var labelsView: some View {
    if highlightParams.labels.count > 0 {
      return AnyView(ScrollView(.horizontal, showsIndicators: false) {
        HStack {
          ForEach(highlightParams.labels, id: \.self) {
            TextChip(feedItemLabel: $0)
              .padding(.leading, 0)
          }
          Spacer()
        }
      }.introspectScrollView { scrollView in
        scrollView.bounces = false
      }
      .padding(.top, 0)
      .padding(.leading, 0)
      .padding(.bottom, 0))
    } else {
      return AnyView(EmptyView())
    }
  }

  var body: some View {
    VStack(alignment: .leading) {
      HStack {
        Spacer()

        Menu(
          content: { contextMenuView },
          label: {
            Image(systemName: "ellipsis")
              .foregroundColor(.appGrayTextContrast)
              .padding()
          }
        )
        .frame(width: 16, height: 16, alignment: .center)
        .onTapGesture { isContextMenuOpen = true }
      }
      .padding(.top, 16)

      if let createdBy = highlightParams.createdBy {
        HStack(alignment: .center) {
          if let profileImageURL = createdBy.profileImageURL, let url = URL(string: profileImageURL) {
            AsyncImage(
              url: url,
              content: { $0.resizable() },
              placeholder: {
                Image(systemName: "person.crop.circle")
                  .resizable()
                  .foregroundColor(.appGrayText)
              }
            )
            .aspectRatio(contentMode: .fill)
            .frame(width: 14, height: 14, alignment: .center)
            .clipShape(Circle())
          } else {
            Image(systemName: "person.crop.circle")
              .resizable()
              .foregroundColor(.appGrayText)
              .frame(width: 14, height: 14)
          }
          Text("\(LocalText.highlightCardHighlightByOther)\(highlightParams.createdBy?.name ?? "you")") // TODO: fix translation...add other/you
            .font(.appFootnote)
            .foregroundColor(.appGrayText)
        }
      }

      HStack {
        Divider()
          .frame(width: 2)
          .overlay(highlightParams.createdBy != nil ? Color(red: 206 / 255.0, green: 239 / 255.0, blue: 159 / 255.0) : Color.appYellow48)
          .opacity(0.8)
          .padding(.top, 2)
          .padding(.trailing, 6)

        VStack(alignment: .leading, spacing: 16) {
          Text(highlightParams.quote)
          labelsView
        }
      }
      .padding(.bottom, 4)

      noteSection
    }
    .sheet(isPresented: $showAnnotationModal) {
      HighlightAnnotationSheet(
        annotation: $annotation,
        onSave: {
          onSaveAnnotation(annotation)
          showAnnotationModal = false
          hasHighlightMutations = true
        },
        onCancel: {
          showAnnotationModal = false
        },
        errorAlertMessage: $errorAlertMessage,
        showErrorAlertMessage: $showErrorAlertMessage
      )
    }
  }
}
