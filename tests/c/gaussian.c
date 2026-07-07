#include "data_arrays.h"

pixel_t blur_image[SIZE - 2][SIZE - 2];

int conv_filter[3][3] = {
    {0, 1, 0},
    {1, 2, 1},
    {0, 1, 0}
};

// Do a 2D convolution with powers of 2 to avoid divides
// Performed on each color on its own
void gaussian_blur(pixel_t image[SIZE][SIZE], pixel_t blur_image[SIZE - 2][SIZE - 2]) {
    // Iterate over entire image, starting one in to avoid edges
    for (int y = 1; y < SIZE - 1; y++) {
        for (int x = 1; x < SIZE - 1; x++) {
            int r_sum = 0, g_sum = 0, b_sum = 0;
            // Iterate over all surrounding pixels, summing according to weight
            for (int fy = -1; fy <= 1; fy++) {
                for (int fx = -1; fx <= 1; fx++) {
                    int shift = conv_filter[fy + 1][fx + 1];
                    int r, g, b;
                    r = image[y + fy][x + fx].r;
                    g = image[y + fy][x + fx].g;
                    b = image[y + fy][x + fx].b;
                    r <<= shift;
                    g <<= shift;
                    b <<= shift;
                    r_sum += r;
                    g_sum += g;
                    b_sum += b;
                }
            }
            // Set the output to be the convolved values
            blur_image[y - 1][x - 1].r = (r_sum >> 4);
            blur_image[y - 1][x - 1].g = (g_sum >> 4);
            blur_image[y - 1][x - 1].b = (b_sum >> 4);
        }
    }
}

// Caclualte a checksum to make sure the image is correct
int checksum(pixel_t blur_image[SIZE - 2][SIZE - 2]) {
    int r_checksum = 0, g_checksum = 0, b_checksum = 0;
    for (int y = 0; y < SIZE - 2; y++) {
        for (int x = 0; x < SIZE - 2; x++) {
            r_checksum += blur_image[y][x].r;
            g_checksum += blur_image[y][x].g;
            b_checksum += blur_image[y][x].b;
        }
    }
    return (r_checksum ^ g_checksum ^ b_checksum);
}

int main() {
    gaussian_blur(image, blur_image);
    return checksum(blur_image);
}
