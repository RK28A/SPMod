import SwiftUI

struct NavigationSectionView: View {
    var color: Color
    var title: String
    var imageSystemName: String
    var subtitle: String? = nil

    var body: some View {
        HStack(spacing: 18) {
            Image(systemName: imageSystemName)
                .font(.system(size: 22, weight: .regular))
                .foregroundColor(.white)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 20, weight: .regular))
                    .foregroundColor(.white)

                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(Color(white: 0.66))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(Color(white: 0.62))
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}
