import SwiftUI

struct NavigationSectionView: View {
    var color: Color
    var title: String
    var imageSystemName: String
    var subtitle: String? = nil

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: imageSystemName)
                .foregroundColor(.white)
                .font(.system(size: 18, weight: .regular))
                .frame(width: 26, height: 26)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)

                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundColor(Color(white: 0.6))
                        .lineLimit(1)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Color(white: 0.5))
        }
        .padding(.vertical, 4)
    }
}
