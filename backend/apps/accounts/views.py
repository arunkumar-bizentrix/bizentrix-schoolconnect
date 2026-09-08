from rest_framework import status, permissions
from rest_framework.views import APIView
from rest_framework.response import Response
from .serializers import LoginSerializer, UserSerializer


class LoginView(APIView):
    """
    POST /api/v1/auth/login/
    Authenticates user and returns JWT access/refresh tokens along with full profile.
    """
    permission_classes = [permissions.AllowAny]

    def post(self, request):
        serializer = LoginSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        return Response(serializer.validated_data, status=status.HTTP_200_OK)


class UserProfileView(APIView):
    """
    GET /api/v1/auth/me/
    Returns the authenticated user's profile and school details.
    """
    permission_classes = [permissions.IsAuthenticated]

    def get(self, request):
        serializer = UserSerializer(request.user)
        return Response(serializer.data, status=status.HTTP_200_OK)
